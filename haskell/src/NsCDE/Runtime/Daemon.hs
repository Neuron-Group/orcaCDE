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

data ProducerStreamStop
  = ProducerStreamDisconnected
  | ProducerStreamRejected
  deriving (Show)

data ServerState = ServerState
  { serverRuntimeState :: RuntimeState
  , serverNextSubscriberId :: Int
  , serverNextEventSeq :: Integer
  , serverSubscribers :: [Subscriber]
  }

data Subscriber = Subscriber
  { subscriberId :: Int
  , subscriberTopics :: [RuntimeTopic]
  , subscriberMode :: SubscriberMode
  , subscriberQueue :: Chan RuntimeResponse
  }

data SubscriberMode
  = SubscriberSnapshots
  | SubscriberEvents Bool
  deriving (Eq, Show)

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
      stateVar <- newMVar (ServerState runtimeState 1 1 [])
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
              [ ("TYPE", "subscribe-events")
              , ("TOPICS", intercalate "," (map renderRuntimeTopic topics))
              , ("BOOTSTRAP", "1")
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
        RequestPublishStream producerRole topics ->
          handleProducerStream stateVar handle producerRole topics
        RequestSubscribe topics ->
          handleSubscription stateVar handle topics SubscriberSnapshots
        RequestSubscribeEvents topics bootstrap ->
          handleSubscription stateVar handle topics (SubscriberEvents bootstrap)
        _ -> do
          response <- handleRequest stateVar request
          writeFrame handle (encodeResponse response)
          hClose handle

handleRequest :: MVar ServerState -> RuntimeRequest -> IO RuntimeResponse
handleRequest stateVar request =
  case request of
    RequestHello maybeRole ->
      pure (ResponseAck ("hello" ++ maybe "" (" " ++) maybeRole))
    RequestPublishStream _ _ ->
      pure (ResponseError "publish-stream requests must use the persistent socket path")
    RequestProducerState _ _ ->
      pure (ResponseError "producer state frames must use the persistent publish-stream path")
    RequestSubscribe _ ->
      pure (ResponseError "subscribe requests must use the persistent socket path")
    RequestSubscribeEvents _ _ ->
      pure (ResponseError "subscribe-events requests must use the persistent socket path")
    RequestQuery topic -> do
      serverState <- readMVar stateVar
      ResponseState topic <$> queryTopicEntries (serverRuntimeState serverState) topic
    RequestCommand command -> do
      (transition, eventFrames) <- modifyMVar stateVar $ \serverState -> do
        transition <- handleRuntimeCommand command (serverRuntimeState serverState)
        let (nextSeq, frames) =
              realizeTransitionEvents
                (serverNextEventSeq serverState)
                (SourceCommand command)
                transition
        writeCompatibilityOutputs (runtimeTransitionState transition)
        pure
          ( serverState
              { serverRuntimeState = runtimeTransitionState transition
              , serverNextEventSeq = nextSeq
              }
          , (transition, frames)
          )
      effectResult <- try (performRuntimeTransitionEffects transition)
      broadcastTopics stateVar (runtimeTransitionTopics transition)
      broadcastEventFrames stateVar eventFrames
      case effectResult of
        Right (message, effectStatuses) -> do
          broadcastEffectStatusEvents stateVar effectStatuses
          pure (ResponseAck message)
        Left err ->
          pure
            (ResponseError
              ("runtime transition failed: " ++ displayException (err :: SomeException)))

handleSubscription :: MVar ServerState -> Handle -> [RuntimeTopic] -> SubscriberMode -> IO ()
handleSubscription stateVar handle requestedTopics mode =
  if null topics
    then do
      writeFrame handle (encodeResponse (ResponseError "subscribe requires at least one topic"))
      hClose handle
    else do
      queue <- newChan
      subscriberKey <- modifyMVar stateVar $ \serverState -> do
        let nextKey = serverNextSubscriberId serverState
            subscriber = Subscriber nextKey topics mode queue
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
          sendInitialState handle topics mode (serverRuntimeState serverState)
          forever $ do
            response <- readChan queue
            writeFrame handle (encodeResponse response))
        (\_ -> pure ())
        `finally` (removeSubscriber stateVar subscriberKey >> hClose handle)
  where
    topics = uniqueTopics requestedTopics

handleProducerStream :: MVar ServerState -> Handle -> RuntimeProducerRole -> [RuntimeTopic] -> IO ()
handleProducerStream stateVar handle producerRole requestedTopics =
  if not (producerTopicsValid producerRole topics)
    then do
      writeFrame handle (encodeResponse (ResponseError "producer stream topic set rejected"))
      hClose handle
    else
      ( catchIOError
          (do
            writeFrame handle (encodeResponse (ResponseAck "producer stream accepted"))
            hFlush handle
            producerLoop)
          (\_ -> pure ())
      ) `finally` hClose handle
  where
    topics = uniqueTopics requestedTopics
    producerLoop =
      catchProducerStop $
        forever $ do
          requestFrame <- readFrame handle
          if null requestFrame
            then stopProducerStream ProducerStreamDisconnected
            else
              case decodeRequest requestFrame of
                Right (RequestProducerState topic entries)
                  | topic `elem` topics -> do
                      (changedTopics, eventFrames) <-
                        applyProducerState stateVar producerRole topic entries
                      broadcastTopics stateVar changedTopics
                      broadcastEventFrames stateVar eventFrames
                Right (RequestProducerState _ _) -> do
                  writeFrame handle (encodeResponse (ResponseError "producer stream topic not owned by role"))
                  hFlush handle
                  stopProducerStream ProducerStreamRejected
                Right _ -> do
                  writeFrame handle (encodeResponse (ResponseError "producer stream only accepts state frames"))
                  hFlush handle
                  stopProducerStream ProducerStreamRejected
                Left message -> do
                  writeFrame handle (encodeResponse (ResponseError message))
                  hFlush handle
                  stopProducerStream ProducerStreamRejected

producerTopicsValid :: RuntimeProducerRole -> [RuntimeTopic] -> Bool
producerTopicsValid producerRole topics =
  not (null topics) && all (`elem` producerTopicsAllowed producerRole) topics

applyProducerState
  :: MVar ServerState
  -> RuntimeProducerRole
  -> RuntimeTopic
  -> [KeyValue]
  -> IO ([RuntimeTopic], [(RuntimeTopic, RuntimeResponse)])
applyProducerState stateVar producerRole topic entries =
  modifyMVar stateVar $ \serverState -> do
    transition <- publishProducerState producerRole topic entries (serverRuntimeState serverState)
    let (nextSeq, frames) =
          realizeTransitionEvents
            (serverNextEventSeq serverState)
            (SourceProducer producerRole)
            transition
    writeCompatibilityOutputs (runtimeTransitionState transition)
    pure
      ( serverState
          { serverRuntimeState = runtimeTransitionState transition
          , serverNextEventSeq = nextSeq
          }
      , (runtimeTransitionTopics transition, frames)
      )

sendInitialState :: Handle -> [RuntimeTopic] -> SubscriberMode -> RuntimeState -> IO ()
sendInitialState handle topics mode runtimeState =
  case mode of
    SubscriberSnapshots ->
      mapM_
        (\topic -> do
          entries <- queryTopicEntries runtimeState topic
          writeFrame handle (encodeResponse (ResponseState topic entries)))
        topics
    SubscriberEvents bootstrapEnabled ->
      when bootstrapEnabled $
        mapM_
          (\topic -> do
            entries <- queryTopicEntries runtimeState topic
            writeFrame handle (encodeResponse (ResponseSnapshot topic entries)))
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

broadcastEventFrames :: MVar ServerState -> [(RuntimeTopic, RuntimeResponse)] -> IO ()
broadcastEventFrames stateVar eventFrames =
  when (not (null eventFrames)) $ do
    serverState <- readMVar stateVar
    mapM_ (broadcastEventFrame (serverSubscribers serverState)) eventFrames

broadcastEventFrame :: [Subscriber] -> (RuntimeTopic, RuntimeResponse) -> IO ()
broadcastEventFrame subscribers (topic, response) =
  mapM_
    (\subscriber ->
      when (subscriberWantsEvents topic subscriber) $
        writeChan (subscriberQueue subscriber) response)
    subscribers

broadcastTopic :: RuntimeState -> [Subscriber] -> RuntimeTopic -> IO ()
broadcastTopic runtimeState subscribers topic = do
  entries <- queryTopicEntries runtimeState topic
  let response = ResponseState topic entries
  mapM_
    (\subscriber ->
      when (subscriberWantsSnapshots topic subscriber) $
        writeChan (subscriberQueue subscriber) response)
    subscribers

subscriberWantsTopic :: RuntimeTopic -> Subscriber -> Bool
subscriberWantsTopic topic subscriber =
  any (== topic) (subscriberTopics subscriber)

subscriberWantsSnapshots :: RuntimeTopic -> Subscriber -> Bool
subscriberWantsSnapshots topic subscriber =
  subscriberWantsTopic topic subscriber &&
    case subscriberMode subscriber of
      SubscriberSnapshots -> True
      SubscriberEvents _ -> False

subscriberWantsEvents :: RuntimeTopic -> Subscriber -> Bool
subscriberWantsEvents topic subscriber =
  subscriberWantsTopic topic subscriber &&
    case subscriberMode subscriber of
      SubscriberSnapshots -> False
      SubscriberEvents _ -> True

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
  (transition, eventFrames) <- modifyMVar stateVar $ \serverState -> do
    transition <- handleCompatCommandLine rawLine (serverRuntimeState serverState)
    let (nextSeq, frames) =
          realizeTransitionEvents
            (serverNextEventSeq serverState)
            SourceCompatFifo
            transition
    writeCompatibilityOutputs (runtimeTransitionState transition)
    pure
      ( serverState
          { serverRuntimeState = runtimeTransitionState transition
          , serverNextEventSeq = nextSeq
          }
      , (transition, frames)
      )
  (_, effectStatuses) <- performRuntimeTransitionEffects transition
  broadcastTopics stateVar (runtimeTransitionTopics transition)
  broadcastEventFrames stateVar eventFrames
  broadcastEffectStatusEvents stateVar effectStatuses

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
    Just "snapshot" ->
      case parseRuntimeTopic (lookupValueDefault "TOPIC" "" frame) of
        Just topic -> Right (ResponseSnapshot topic (stripMeta frame))
        Nothing -> Left "unsupported snapshot topic"
    Just "event" ->
      decodeEventResponse frame
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
    CommandColorSelect paletteName colorCount ->
      [ ("TYPE", "command")
      , ("NAME", "color-select")
      , ("PALETTE", paletteName)
      , ("COLORS", show colorCount)
      ]
    CommandBackdropSelect deskNumber modeText imageName ->
      [ ("TYPE", "command")
      , ("NAME", "backdrop-select")
      , ("DESK", show deskNumber)
      , ("MODE", modeText)
      , ("IMAGE", imageName)
      ]
    CommandReload ->
      [ ("TYPE", "command")
      , ("NAME", "reload")
      ]
    CommandRefresh refreshTarget ->
      [ ("TYPE", "command")
      , ("NAME", "refresh")
      , ("TARGET", renderRuntimeRefreshTarget refreshTarget)
      ]
    CommandLogout ->
      [ ("TYPE", "command")
      , ("NAME", "logout")
      ]
    CommandFailsafe ->
      [ ("TYPE", "command")
      , ("NAME", "failsafe")
      ]
    CommandPower powerAction ->
      [ ("TYPE", "command")
      , ("NAME", "power")
      , ("ACTION", renderPowerAction powerAction)
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

renderPowerAction :: RuntimePowerAction -> String
renderPowerAction powerAction =
  case powerAction of
    PowerShutdown -> "poweroff"
    PowerReboot -> "reboot"
    PowerSuspend -> "suspend"
    PowerHybridSuspend -> "hybrid-suspend"
    PowerHibernate -> "hibernate"

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
  filter (\(key, _) ->
    key /= "TYPE"
      && key /= "TOPIC"
      && key /= "SEQ"
      && key /= "EVENT"
      && key /= "SOURCE"
      && key /= "RESET"
      && key /= "UNSET")

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

stopProducerStream :: ProducerStreamStop -> IO a
stopProducerStream reason =
  ioError (userError (show reason))

catchProducerStop :: IO () -> IO ()
catchProducerStop action =
  catchIOError action $ \err ->
    case show err of
      "ProducerStreamDisconnected" -> pure ()
      "ProducerStreamRejected" -> pure ()
      _ -> ioError err

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

realizeTransitionEvents
  :: Integer
  -> RuntimeEventSource
  -> RuntimeTransition
  -> (Integer, [(RuntimeTopic, RuntimeResponse)])
realizeTransitionEvents startSeq eventSource transition =
  foldl buildFrame (startSeq, []) (runtimeTransitionEventDeltas transition)
  where
    buildFrame (nextSeq, frames) eventDelta =
      let event =
            RuntimeEvent
              { runtimeEventSeq = nextSeq
              , runtimeEventTopic = runtimeEventDeltaTopic eventDelta
              , runtimeEventKind = runtimeEventDeltaKind eventDelta
              , runtimeEventSource = eventSource
              , runtimeEventReset = runtimeEventDeltaReset eventDelta
              , runtimeEventUnsetKeys = runtimeEventDeltaUnsetKeys eventDelta
              }
      in
        ( nextSeq + 1
        , frames ++
            [ ( runtimeEventDeltaTopic eventDelta
              , ResponseEvent event (runtimeEventDeltaEntries eventDelta)
              )
            ]
        )

decodeEventResponse :: [KeyValue] -> Either String RuntimeResponse
decodeEventResponse frame =
  case ( parseRuntimeTopic (lookupValueDefault "TOPIC" "" frame)
       , parseRuntimeEventKind (lookupValueDefault "EVENT" "" frame)
       , reads (lookupValueDefault "SEQ" "" frame)
       ) of
    (Just topic, Just eventKind, [(seqValue, "")]) ->
      Right
        (ResponseEvent
          RuntimeEvent
            { runtimeEventSeq = seqValue
            , runtimeEventTopic = topic
            , runtimeEventKind = eventKind
            , runtimeEventSource = parseEventSource (lookupValueDefault "SOURCE" "" frame)
            , runtimeEventReset = lookupValueDefault "RESET" "0" frame == "1"
            , runtimeEventUnsetKeys = parseCommaList (lookupValueDefault "UNSET" "" frame)
            }
          (stripMeta frame))
    _ ->
      Left "unsupported event frame"

broadcastEffectStatusEvents :: MVar ServerState -> [RuntimeEffectStatus] -> IO ()
broadcastEffectStatusEvents stateVar effectStatuses =
  when (not (null failedStatuses)) $ do
    frames <- modifyMVar stateVar $ \serverState -> do
      let (nextSeq, nextFrames) =
            realizeEffectStatusEvents
              (serverNextEventSeq serverState)
              failedStatuses
      pure
        ( serverState { serverNextEventSeq = nextSeq }
        , nextFrames
        )
    broadcastEventFrames stateVar frames
  where
    failedStatuses = filter (not . runtimeEffectSucceeded) effectStatuses

realizeEffectStatusEvents
  :: Integer
  -> [RuntimeEffectStatus]
  -> (Integer, [(RuntimeTopic, RuntimeResponse)])
realizeEffectStatusEvents startSeq =
  foldl buildFrame (startSeq, [])
  where
    buildFrame (nextSeq, frames) effectStatus =
      let event =
            RuntimeEvent
              { runtimeEventSeq = nextSeq
              , runtimeEventTopic = TopicSession
              , runtimeEventKind = EventBackendActionFailed
              , runtimeEventSource = SourceEffect
              , runtimeEventReset = False
              , runtimeEventUnsetKeys = []
              }
          response =
            ResponseEvent event
              [ ("EFFECT", renderEffectName (runtimeEffectValue effectStatus)) ]
      in (nextSeq + 1, frames ++ [(TopicSession, response)])

renderEffectName :: RuntimeEffect -> String
renderEffectName effect =
  case effect of
    RuntimeEffectCompatCommand _ _ -> "compat-command"
    RuntimeEffectApplyResolvedStyle _ -> "apply-resolved-style"
    RuntimeEffectRefreshLabwc _ -> "refresh-labwc"
    RuntimeEffectPower _ -> "power"
    RuntimeEffectFailsafeTerminal -> "failsafe-terminal"
    RuntimeEffectLogoutBackend -> "logout-backend"
    RuntimeEffectReloadBackend -> "reload-backend"

parseEventSource :: String -> RuntimeEventSource
parseEventSource rawSource =
  case rawSource of
    "startup" -> SourceStartup
    "compat-fifo" -> SourceCompatFifo
    "effect" -> SourceEffect
    _ ->
      case splitOnFirst ':' rawSource of
        Just ("producer", "pagerd") -> SourceProducer ProducerPager
        Just ("producer", "toplevel") -> SourceProducer ProducerToplevel
        _ -> SourceEffect

parseCommaList :: String -> [String]
parseCommaList "" = []
parseCommaList rawText =
  filter (not . null) (splitComma rawText)

splitComma :: String -> [String]
splitComma [] = [""]
splitComma (',':rest) = "" : splitComma rest
splitComma (char:rest) =
  case splitComma rest of
    [] -> [[char]]
    token:tokens -> (char : token) : tokens

splitOnFirst :: Char -> String -> Maybe (String, String)
splitOnFirst delimiter rawText =
  case break (== delimiter) rawText of
    (_, "") -> Nothing
    (left, _ : right) -> Just (left, right)
