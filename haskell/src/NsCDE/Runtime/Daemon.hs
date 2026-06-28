module NsCDE.Runtime.Daemon
  ( runCtl
  , runDaemon
  , runPublishState
  , runQuery
  , runSubscribe
  ) where

import Control.Concurrent
  ( Chan
  , MVar
  , forkIO
  , modifyMVar
  , modifyMVar_
  , newChan
  , newMVar
  , readChan
  , readMVar
  , threadWaitRead
  , writeChan
  )
import Control.Exception (SomeException, displayException, finally, try)
import Control.Monad (forever, void, when)
import Data.List (intercalate)
import Network.Socket
import System.Directory (createDirectoryIfMissing, removeFile)
import System.Environment (getEnvironment)
import System.Exit (exitFailure)
import System.IO
  ( BufferMode(..)
  , Handle
  , IOMode(ReadWriteMode)
  , hClose
  , hFlush
  , hPutStrLn
  , hSetBuffering
  , stderr
  , stdout
  )
import System.IO.Error (catchIOError)
import System.Posix.IO
  ( OpenFileFlags(..)
  , OpenMode(ReadOnly)
  , closeFd
  , defaultFileFlags
  , fdRead
  , openFd
  )
import System.Posix.Process (getProcessID)
import System.Posix.Types (ProcessID)

import NsCDE.Domain.Runtime
import NsCDE.Foundation.EnvFile (KeyValue, renderEnvFile)
import NsCDE.Foundation.Paths
  ( RuntimePaths
  , resolveRuntimePaths
  , runtimeCommandFifo
  , runtimePidFile
  , runtimeSocketFile
  , runtimeStateDir
  )
import NsCDE.Runtime.Protocol
import NsCDE.Runtime.State

data ServerState = ServerState
  { serverRuntimeState :: RuntimeState
  , serverNextSubscriberId :: Int
  , serverSubscribers :: [Subscriber]
  }

data Subscriber = Subscriber
  { subscriberId :: Int
  , subscriberTopics :: [RuntimeTopic]
  , subscriberQueue :: Chan RuntimeResponse
  }

runDaemon :: IO ()
runDaemon = do
  env <- getEnvironment
  runtimeState <- loadRuntimeState env
  createDirectoryIfMissing True (runtimeStateDir (runtimePaths runtimeState))
  ensureCompatibilityFifos runtimeState
  writeCompatibilityOutputs runtimeState
  writePid runtimeState
  cleanupSocket (runtimeSocketFile (runtimePaths runtimeState))
  withSocketsDo $
    bracketSocket (runtimeSocketFile (runtimePaths runtimeState)) $ \serverSocket -> do
      stateVar <- newMVar (ServerState runtimeState 1 [])
      void (forkIO (fifoLoop stateVar))
      forever $ do
        (clientSocket, _) <- accept serverSocket
        void (forkIO (handleClient stateVar clientSocket))

runCtl :: RuntimeCommand -> IO ()
runCtl command = do
  env <- getEnvironment
  let paths = resolveRuntimePaths env
  maybeResponse <- requestServer paths (commandFrame command)
  case maybeResponse of
    Just responseFrame ->
      case decodeServerResponse responseFrame of
        Left message -> failWith message
        Right (ResponseError message) -> failWith message
        Right _ -> pure ()
    Nothing -> do
      handled <- fallbackCommand env command
      when (not handled) $
        failWith "runtime daemon and compatibility control path are unavailable"

runPublishState :: RuntimeTopic -> [KeyValue] -> IO ()
runPublishState topic entries =
  runCtl (CommandPublishState topic entries)

runQuery :: RuntimeTopic -> IO ()
runQuery topic = do
  env <- getEnvironment
  let paths = resolveRuntimePaths env
  maybeResponse <- requestServer paths [("TYPE", "query"), ("TOPIC", renderRuntimeTopic topic)]
  entries <-
    case maybeResponse of
      Just responseFrame ->
        case decodeServerResponse responseFrame of
          Right (ResponseState _ responseEntries) -> pure responseEntries
          Right (ResponseError message) -> failWith message >> pure []
          Left message -> failWith message >> pure []
          Right _ -> pure []
      Nothing ->
        fallbackQuery env topic
  putStr (renderEnvFile entries)

runSubscribe :: [RuntimeTopic] -> IO ()
runSubscribe requestedTopics =
  if null topics
    then failWith "subscribe requires at least one topic"
    else do
      env <- getEnvironment
      let paths = resolveRuntimePaths env
      withSocketsDo $
        catchIOError
          (do
            clientSocket <- socket AF_UNIX Stream defaultProtocol
            connect clientSocket (SockAddrUnix (runtimeSocketFile paths))
            handle <- socketToHandle clientSocket ReadWriteMode
            hSetBuffering handle LineBuffering
            writeFrame
              handle
              [ ("TYPE", "subscribe")
              , ("TOPICS", intercalate "," (map renderRuntimeTopic topics))
              ]
            streamSubscription handle)
          (\_ -> failWith "runtime daemon subscribe path is unavailable")
  where
    topics = uniqueTopics requestedTopics

handleClient :: MVar ServerState -> Socket -> IO ()
handleClient stateVar clientSocket = do
  handle <- socketToHandle clientSocket ReadWriteMode
  hSetBuffering handle LineBuffering
  requestFrame <- readFrame handle
  case decodeRequest requestFrame of
    Left message -> do
      writeFrame handle (encodeResponse (ResponseError message))
      hClose handle
    Right request ->
      case request of
        RequestSubscribe topics ->
          handleSubscription stateVar handle topics
        _ -> do
          response <- handleRequest stateVar request
          writeFrame handle (encodeResponse response)
          hClose handle

handleRequest :: MVar ServerState -> RuntimeRequest -> IO RuntimeResponse
handleRequest stateVar request =
  case request of
    RequestHello maybeRole ->
      pure (ResponseAck ("hello" ++ maybe "" (" " ++) maybeRole))
    RequestSubscribe _ ->
      pure (ResponseError "subscribe requests must use the persistent socket path")
    RequestQuery topic -> do
      serverState <- readMVar stateVar
      ResponseState topic <$> queryTopicEntries (serverRuntimeState serverState) topic
    RequestCommand command -> do
      transition <- modifyMVar stateVar $ \serverState -> do
        transition <- handleRuntimeCommand command (serverRuntimeState serverState)
        writeCompatibilityOutputs (runtimeTransitionState transition)
        pure
          ( serverState {serverRuntimeState = runtimeTransitionState transition}
          , transition
          )
      effectResult <- try (performRuntimeTransitionEffects transition)
      broadcastTopics stateVar (runtimeTransitionTopics transition)
      case effectResult of
        Right message ->
          pure (ResponseAck message)
        Left err ->
          pure
            (ResponseError
              ("runtime transition failed: " ++ displayException (err :: SomeException)))

handleSubscription :: MVar ServerState -> Handle -> [RuntimeTopic] -> IO ()
handleSubscription stateVar handle requestedTopics =
  if null topics
    then do
      writeFrame handle (encodeResponse (ResponseError "subscribe requires at least one topic"))
      hClose handle
    else do
      queue <- newChan
      subscriberKey <- modifyMVar stateVar $ \serverState -> do
        let nextKey = serverNextSubscriberId serverState
            subscriber = Subscriber nextKey topics queue
        pure
          ( serverState
              { serverNextSubscriberId = nextKey + 1
              , serverSubscribers = subscriber : serverSubscribers serverState
              }
          , nextKey
          )
      catchIOError
        (do
          serverState <- readMVar stateVar
          sendInitialState handle topics (serverRuntimeState serverState)
          forever $ do
            response <- readChan queue
            writeFrame handle (encodeResponse response))
        (\_ -> pure ())
        `finally` (removeSubscriber stateVar subscriberKey >> hClose handle)
  where
    topics = uniqueTopics requestedTopics

sendInitialState :: Handle -> [RuntimeTopic] -> RuntimeState -> IO ()
sendInitialState handle topics runtimeState =
  mapM_
    (\topic -> do
      entries <- queryTopicEntries runtimeState topic
      writeFrame handle (encodeResponse (ResponseState topic entries)))
    topics

removeSubscriber :: MVar ServerState -> Int -> IO ()
removeSubscriber stateVar subscriberKey =
  modifyMVar_ stateVar $ \serverState ->
    pure
      serverState
        { serverSubscribers =
            filter ((/= subscriberKey) . subscriberId) (serverSubscribers serverState)
        }

broadcastTopics :: MVar ServerState -> [RuntimeTopic] -> IO ()
broadcastTopics stateVar changedTopics =
  when (not (null topics)) $ do
    serverState <- readMVar stateVar
    let runtimeState = serverRuntimeState serverState
        subscribers = serverSubscribers serverState
    mapM_ (broadcastTopic runtimeState subscribers) topics
  where
    topics = uniqueTopics changedTopics

broadcastTopic :: RuntimeState -> [Subscriber] -> RuntimeTopic -> IO ()
broadcastTopic runtimeState subscribers topic = do
  entries <- queryTopicEntries runtimeState topic
  let response = ResponseState topic entries
  mapM_
    (\subscriber ->
      when (subscriberWantsTopic topic subscriber) $
        writeChan (subscriberQueue subscriber) response)
    subscribers

subscriberWantsTopic :: RuntimeTopic -> Subscriber -> Bool
subscriberWantsTopic topic subscriber =
  any (== topic) (subscriberTopics subscriber)

uniqueTopics :: [RuntimeTopic] -> [RuntimeTopic]
uniqueTopics =
  foldr insertTopic []
  where
    insertTopic topic acc
      | topic `elem` acc = acc
      | otherwise = topic : acc

fifoLoop :: MVar ServerState -> IO ()
fifoLoop stateVar = do
  serverState <- readMVar stateVar
  let fifoPath = runtimeCommandFifo (runtimePaths (serverRuntimeState serverState))
  fd <- openFd fifoPath ReadOnly defaultFileFlags {nonBlock = True}
  loop fd ""
  where
    loop fd leftover = do
      threadWaitRead fd
      readResult <- catchIOError (Just <$> fdRead fd 4096) (\_ -> pure Nothing)
      case readResult of
        Nothing -> do
          closeFd fd
          serverState <- readMVar stateVar
          let fifoPath = runtimeCommandFifo (runtimePaths (serverRuntimeState serverState))
          newFd <- openFd fifoPath ReadOnly defaultFileFlags {nonBlock = True}
          loop newFd leftover
        Just (chunk, _) -> do
          if null chunk
            then do
              closeFd fd
              serverState <- readMVar stateVar
              let fifoPath = runtimeCommandFifo (runtimePaths (serverRuntimeState serverState))
              newFd <- openFd fifoPath ReadOnly defaultFileFlags {nonBlock = True}
              loop newFd leftover
            else do
              let (nextLeftover, completeLines) = extractLines leftover chunk
              mapM_ (applyCompatLine stateVar) completeLines
              loop fd nextLeftover

applyCompatLine :: MVar ServerState -> String -> IO ()
applyCompatLine stateVar rawLine = do
  transition <- modifyMVar stateVar $ \serverState -> do
    transition <- handleCompatCommandLine rawLine (serverRuntimeState serverState)
    writeCompatibilityOutputs (runtimeTransitionState transition)
    pure
      ( serverState {serverRuntimeState = runtimeTransitionState transition}
      , transition
      )
  _ <- performRuntimeTransitionEffects transition
  broadcastTopics stateVar (runtimeTransitionTopics transition)

requestServer :: RuntimePaths -> [KeyValue] -> IO (Maybe [KeyValue])
requestServer paths requestFrame =
  catchIOError
    (withSocketsDo $ do
      clientSocket <- socket AF_UNIX Stream defaultProtocol
      connect clientSocket (SockAddrUnix (runtimeSocketFile paths))
      handle <- socketToHandle clientSocket ReadWriteMode
      hSetBuffering handle LineBuffering
      writeFrame handle requestFrame
      responseFrame <- readFrame handle
      hClose handle
      pure (Just responseFrame))
    (\_ -> pure Nothing)

decodeServerResponse :: [KeyValue] -> Either String RuntimeResponse
decodeServerResponse frame =
  case lookupValue "TYPE" frame of
    Just "ack" -> Right (ResponseAck (lookupValueDefault "MESSAGE" "" frame))
    Just "error" -> Right (ResponseError (lookupValueDefault "MESSAGE" "unknown error" frame))
    Just "state" ->
      case parseRuntimeTopic (lookupValueDefault "TOPIC" "" frame) of
        Just topic -> Right (ResponseState topic (stripMeta frame))
        Nothing -> Left "unsupported state topic"
    _ -> Left "unsupported response type"

commandFrame :: RuntimeCommand -> [KeyValue]
commandFrame command =
  case command of
    CommandWorkspaceSwitch workspaceName ->
      [ ("TYPE", "command")
      , ("NAME", "workspace-switch")
      , ("WORKSPACE", workspaceName)
      ]
    CommandWorkspaceRename oldWorkspace newWorkspace ->
      [ ("TYPE", "command")
      , ("NAME", "workspace-rename")
      , ("OLD", oldWorkspace)
      , ("NEW", newWorkspace)
      ]
    CommandReload ->
      [ ("TYPE", "command")
      , ("NAME", "reload")
      ]
    CommandPublishState topic entries ->
      [ ("TYPE", "command")
      , ("NAME", "publish-state")
      , ("TOPIC", renderRuntimeTopic topic)
      ] ++ entries
    CommandStyleSet styleEntries applyNow ->
      [ ("TYPE", "command")
      , ("NAME", "style-set")
      , ("APPLY", if applyNow then "1" else "0")
      ] ++ styleEntries
    CommandStyleApply ->
      [ ("TYPE", "command")
      , ("NAME", "style-apply")
      ]
    CommandWindow windowCommand windowId ->
      [ ("TYPE", "command")
      , ("NAME", "window-" ++ renderRuntimeWindowCommand windowCommand)
      , ("ID", show windowId)
      ]

cleanupSocket :: FilePath -> IO ()
cleanupSocket socketPath =
  catchIOError (removeFile socketPath) (\_ -> pure ())

bracketSocket :: FilePath -> (Socket -> IO a) -> IO a
bracketSocket socketPath action = do
  serverSocket <- socket AF_UNIX Stream defaultProtocol
  bind serverSocket (SockAddrUnix socketPath)
  listen serverSocket maxListenQueue
  action serverSocket `finally` (close serverSocket >> cleanupSocket socketPath)

writePid :: RuntimeState -> IO ()
writePid runtimeState = do
  pid <- getProcessID
  let pidPath = runtimePidFile (runtimePaths runtimeState)
  writeFile pidPath (showPid pid ++ "\n")

showPid :: ProcessID -> String
showPid = show

extractLines :: String -> String -> (String, [String])
extractLines leftover chunk =
  let combined = leftover ++ chunk
      combinedLines = lines combined
  in case reverse combined of
       '\n':_ -> ("", combinedLines)
       _ ->
         case reverse combinedLines of
           [] -> (combined, [])
           trailing:rest -> (trailing, reverse rest)

stripMeta :: [KeyValue] -> [KeyValue]
stripMeta =
  filter (\(key, _) -> key /= "TYPE" && key /= "TOPIC")

lookupValue :: String -> [KeyValue] -> Maybe String
lookupValue _ [] = Nothing
lookupValue key ((candidate, value):rest)
  | key == candidate = Just value
  | otherwise = lookupValue key rest

lookupValueDefault :: String -> String -> [KeyValue] -> String
lookupValueDefault key fallback frame =
  case lookupValue key frame of
    Just value -> value
    Nothing -> fallback

failWith :: String -> IO ()
failWith message = do
  hPutStrLn stderr message
  exitFailure

streamSubscription :: Handle -> IO ()
streamSubscription handle =
  finally loop (hClose handle)
  where
    loop = do
      frame <- readFrame handle
      if null frame
        then pure ()
        else do
          putStr (renderFrame frame)
          hFlush stdout
          loop
