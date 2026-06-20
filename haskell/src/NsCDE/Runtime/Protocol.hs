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
    "subscribe" ->
      let topics = mapMaybe parseRuntimeTopic (splitCommaList (lookupText frame "TOPICS" ""))
      in Right (RequestSubscribe topics)
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
    ResponseAck message ->
      [ ("TYPE", "ack")
      , ("MESSAGE", message)
      ]
    ResponseError message ->
      [ ("TYPE", "error")
      , ("MESSAGE", message)
      ]

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
       "reload" ->
         Right (RequestCommand CommandReload)
       "style-set" ->
         Right
           (RequestCommand
             (CommandStyleSet
               (styleSetEntries frame)
               (lookupText frame "APPLY" "0" == "1")))
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

isPrefixOf :: Eq a => [a] -> [a] -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (left:leftRest) (right:rightRest) =
  left == right && isPrefixOf leftRest rightRest
