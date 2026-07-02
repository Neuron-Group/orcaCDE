module NsCDE.Runtime.Protocol
  ( decodeRequest
  , encodeResponse
  , readFrame
  , renderFrame
  , writeFrame
  ) where

import System.IO (Handle, hGetLine, hIsEOF, hPutStr)

import NsCDE.Domain.Runtime
import NsCDE.Foundation.Common (splitCommaList, trim)
import NsCDE.Foundation.EnvFile (KeyValue, parseEnvLine, renderEnvFile)
import NsCDE.Foundation.Settings (lookupText, lookupValue)

readFrame :: Handle -> IO [KeyValue]
readFrame handle =
  go []
  where
    go acc = do
      eof <- hIsEOF handle
      if eof
        then pure (reverse acc)
        else do
          rawLine <- hGetLine handle
          let line =
                case reverse rawLine of
                  '\r':rest -> reverse rest
                  _ -> rawLine
          if null line
            then pure (reverse acc)
            else case parseEnvLine line of
                   Just entry -> go (entry : acc)
                   Nothing -> go acc

renderFrame :: [KeyValue] -> String
renderFrame entries =
  renderEnvFile entries ++ "\n"

writeFrame :: Handle -> [KeyValue] -> IO ()
writeFrame handle =
  hPutStr handle . renderFrame

decodeRequest :: [KeyValue] -> Either String RuntimeRequest
decodeRequest frame =
  case lookupText frame "TYPE" "" of
    "hello" ->
      Right (RequestHello (lookupValue frame "ROLE"))
    "publish-stream" ->
      decodePublishStream frame
    "subscribe" ->
      let topics = mapMaybe parseRuntimeTopic (splitCommaList (lookupText frame "TOPICS" ""))
      in Right (RequestSubscribe topics)
    "subscribe-events" ->
      let topics = mapMaybe parseRuntimeTopic (splitCommaList (lookupText frame "TOPICS" ""))
          bootstrap = lookupText frame "BOOTSTRAP" "1" /= "0"
      in Right (RequestSubscribeEvents topics bootstrap)
    "state" ->
      case parseRuntimeTopic (lookupText frame "TOPIC" "") of
        Just topic -> Right (RequestProducerState topic (publishStateEntries frame))
        Nothing -> Left "unsupported producer state topic"
    "query" ->
      case parseRuntimeTopic (lookupText frame "TOPIC" "") of
        Just topic -> Right (RequestQuery topic)
        Nothing -> Left "unsupported query topic"
    "command" ->
      decodeCommand frame
    _ ->
      Left "unsupported request type"

encodeResponse :: RuntimeResponse -> [KeyValue]
encodeResponse response =
  case response of
    ResponseState topic entries ->
      [ ("TYPE", "state")
      , ("TOPIC", renderRuntimeTopic topic)
      ] ++ entries
    ResponseSnapshot topic entries ->
      [ ("TYPE", "snapshot")
      , ("TOPIC", renderRuntimeTopic topic)
      ] ++ entries
    ResponseEvent event entries ->
      [ ("TYPE", "event")
      , ("TOPIC", renderRuntimeTopic (runtimeEventTopic event))
      , ("SEQ", show (runtimeEventSeq event))
      , ("EVENT", renderRuntimeEventKind (runtimeEventKind event))
      , ("SOURCE", renderRuntimeEventSource (runtimeEventSource event))
      , ("RESET", if runtimeEventReset event then "1" else "0")
      , ("UNSET", intercalateComma (runtimeEventUnsetKeys event))
      ] ++ entries
    ResponseAck message ->
      [ ("TYPE", "ack")
      , ("MESSAGE", message)
      ]
    ResponseError message ->
      [ ("TYPE", "error")
      , ("MESSAGE", message)
      ]

decodePublishStream :: [KeyValue] -> Either String RuntimeRequest
decodePublishStream frame =
  case parseRuntimeProducerRole (lookupText frame "ROLE" "") of
    Just producerRole ->
      let topics = mapMaybe parseRuntimeTopic (splitCommaList (lookupText frame "TOPICS" ""))
      in Right (RequestPublishStream producerRole topics)
    Nothing ->
      Left "unsupported producer role"

decodeCommand :: [KeyValue] -> Either String RuntimeRequest
decodeCommand frame =
  let commandName = trim (lookupText frame "NAME" "")
  in case commandName of
       "workspace-switch" ->
         Right (RequestCommand (CommandWorkspaceSwitch (lookupText frame "WORKSPACE" "")))
       "workspace-rename" ->
         Right
           (RequestCommand
             (CommandWorkspaceRename
               (lookupText frame "OLD" "")
               (lookupText frame "NEW" "")))
       "publish-state" ->
         case parseRuntimeTopic (lookupText frame "TOPIC" "") of
           Just topic ->
             Right
               (RequestCommand
                 (CommandPublishState topic (publishStateEntries frame)))
           Nothing ->
             Left "unsupported publish topic"
       "reload" ->
         Right (RequestCommand CommandReload)
       "refresh" ->
         case parseRuntimeRefreshTarget (lookupText frame "TARGET" "") of
           Just refreshTarget ->
             Right (RequestCommand (CommandRefresh refreshTarget))
           Nothing ->
             Left "unsupported refresh target"
       "logout" ->
         Right (RequestCommand CommandLogout)
       "failsafe" ->
         Right (RequestCommand CommandFailsafe)
       "power" ->
         case lookupText frame "ACTION" "" of
           "poweroff" -> Right (RequestCommand (CommandPower PowerShutdown))
           "reboot" -> Right (RequestCommand (CommandPower PowerReboot))
           "suspend" -> Right (RequestCommand (CommandPower PowerSuspend))
           "hybrid-suspend" -> Right (RequestCommand (CommandPower PowerHybridSuspend))
           "hibernate" -> Right (RequestCommand (CommandPower PowerHibernate))
           _ -> Left "unsupported power action"
       "style-set" ->
         Right
           (RequestCommand
             (CommandStyleSet
               (styleSetEntries frame)
               (lookupText frame "APPLY" "0" == "1")))
       "color-select" ->
         case reads (lookupText frame "COLORS" "") of
           [(colorCount, "")] ->
             Right
               (RequestCommand
                 (CommandColorSelect
                   (lookupText frame "PALETTE" "")
                   colorCount))
           _ ->
             Left "invalid color count"
       "backdrop-select" ->
         case reads (lookupText frame "DESK" "") of
           [(deskNumber, "")] ->
             Right
               (RequestCommand
                 (CommandBackdropSelect
                   deskNumber
                   (lookupText frame "MODE" "")
                   (lookupText frame "IMAGE" "")))
           _ ->
             Left "invalid desk number"
       "style-apply" ->
         Right (RequestCommand CommandStyleApply)
       _ | "window-" `isPrefixOf` commandName ->
             case parseRuntimeWindowCommand (drop (length ("window-" :: String)) commandName) of
               Just windowCommand ->
                 case reads (lookupText frame "ID" "") of
                   [(windowId, "")] ->
                     Right (RequestCommand (CommandWindow windowCommand windowId))
                   _ ->
                     Left "invalid window id"
               Nothing ->
                 Left "unsupported window command"
         | otherwise ->
             Left "unsupported command"

mapMaybe :: (a -> Maybe b) -> [a] -> [b]
mapMaybe _ [] = []
mapMaybe fn (value:rest) =
  case fn value of
    Just result -> result : mapMaybe fn rest
    Nothing -> mapMaybe fn rest

styleSetEntries :: [KeyValue] -> [KeyValue]
styleSetEntries =
  filter keepEntry
  where
    keepEntry (key, _) =
      key /= "TYPE" && key /= "NAME" && key /= "APPLY"

publishStateEntries :: [KeyValue] -> [KeyValue]
publishStateEntries =
  filter keepEntry
  where
    keepEntry (key, _) =
      key /= "TYPE" && key /= "NAME" && key /= "TOPIC"

isPrefixOf :: Eq a => [a] -> [a] -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (left:leftRest) (right:rightRest) =
  left == right && isPrefixOf leftRest rightRest

intercalateComma :: [String] -> String
intercalateComma [] = ""
intercalateComma [value] = value
intercalateComma (value:rest) = value ++ "," ++ intercalateComma rest
