module NsCDE.Runtime.Daemon
  ( runCtl
  , runDaemon
  , runQuery
  ) where

import Control.Concurrent (MVar, forkIO, modifyMVar, modifyMVar_, newMVar, readMVar, threadDelay)
import Control.Exception (bracket, finally)
import Control.Monad (forever, void, when)
import Network.Socket
import System.Directory (createDirectoryIfMissing, removeFile)
import System.Environment (getEnvironment)
import System.Exit (exitFailure)
import System.IO (BufferMode(..), IOMode(ReadWriteMode), hClose, hPutStrLn, hSetBuffering, stderr)
import System.IO.Error (catchIOError)
import System.Posix.IO (OpenFileFlags(..), OpenMode(ReadOnly), closeFd, defaultFileFlags, fdRead, openFd)
import System.Posix.Process (getProcessID)
import System.Posix.Types (ProcessID)

import NsCDE.Domain.Runtime
import NsCDE.Foundation.EnvFile (KeyValue, renderEnvFile)
import NsCDE.Foundation.Paths (RuntimePaths, resolveRuntimePaths, runtimeCommandFifo, runtimePidFile, runtimeSocketFile, runtimeStateDir)
import NsCDE.Runtime.Protocol
import NsCDE.Runtime.State

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
      stateVar <- newMVar runtimeState
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

handleClient :: MVar RuntimeState -> Socket -> IO ()
handleClient stateVar clientSocket =
  bracket (socketToHandle clientSocket ReadWriteMode) hClose $ \handle -> do
    hSetBuffering handle LineBuffering
    requestFrame <- readFrame handle
    response <-
      case decodeRequest requestFrame of
        Left message -> pure (ResponseError message)
        Right request ->
          case request of
            RequestHello maybeRole ->
              pure (ResponseAck ("hello" ++ maybe "" (" " ++) maybeRole))
            RequestSubscribe _ ->
              pure (ResponseError "subscribe is not implemented yet")
            RequestQuery topic -> do
              runtimeState <- readMVar stateVar
              ResponseState topic <$> queryTopicEntries runtimeState topic
            RequestCommand command -> do
              message <- modifyMVar stateVar $ \runtimeState -> do
                (updatedState, message) <- handleRuntimeCommand command runtimeState
                writeCompatibilityOutputs updatedState
                pure (updatedState, message)
              pure (ResponseAck message)
    writeFrame handle (encodeResponse response)

fifoLoop :: MVar RuntimeState -> IO ()
fifoLoop stateVar = do
  runtimeState <- readMVar stateVar
  let fifoPath = runtimeCommandFifo (runtimePaths runtimeState)
  fd <- openFd fifoPath ReadOnly defaultFileFlags {nonBlock = True}
  loop fd ""
  where
    loop fd leftover = do
      readResult <- catchIOError (Just <$> fdRead fd 4096) (\_ -> pure Nothing)
      case readResult of
        Nothing -> do
          closeFd fd
          runtimeState <- readMVar stateVar
          let fifoPath = runtimeCommandFifo (runtimePaths runtimeState)
          newFd <- openFd fifoPath ReadOnly defaultFileFlags {nonBlock = True}
          loop newFd leftover
        Just (chunk, _) -> do
          when (null chunk) $
            threadDelay 200000
          let (nextLeftover, completeLines) = extractLines leftover chunk
          mapM_ (applyCompatLine stateVar) completeLines
          loop fd nextLeftover

applyCompatLine :: MVar RuntimeState -> String -> IO ()
applyCompatLine stateVar rawLine =
  modifyMVar_ stateVar $ \runtimeState -> do
    (updatedState, _) <- handleCompatCommandLine rawLine runtimeState
    writeCompatibilityOutputs updatedState
    pure updatedState

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
