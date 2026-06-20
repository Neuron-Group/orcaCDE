module NsCDE.Foundation.EnvFile
  ( KeyValue
  , parseEnvContents
  , parseEnvLine
  , readEnvFile
  , readEnvFileIfExists
  , renderEnvFile
  ) where

import Data.Char (isSpace)
import System.Directory (doesFileExist)

type KeyValue = (String, String)

parseEnvContents :: String -> [KeyValue]
parseEnvContents contents =
  foldr collectLine [] (lines contents)

parseEnvLine :: String -> Maybe KeyValue
parseEnvLine = parseLine

readEnvFile :: FilePath -> IO [KeyValue]
readEnvFile path = do
  contents <- readFile path
  pure (parseEnvContents contents)

readEnvFileIfExists :: FilePath -> IO [KeyValue]
readEnvFileIfExists path = do
  exists <- doesFileExist path
  if exists
    then readEnvFile path
    else pure []

renderEnvFile :: [KeyValue] -> String
renderEnvFile entries =
  unlines [key ++ "=" ++ value | (key, value) <- entries]

collectLine :: String -> [KeyValue] -> [KeyValue]
collectLine rawLine acc =
  case parseLine rawLine of
    Nothing -> acc
    Just entry -> entry : acc

parseLine :: String -> Maybe KeyValue
parseLine rawLine =
  let line = trim rawLine
  in case line of
       "" -> Nothing
       ('#':_) -> Nothing
       _ ->
         case break (== '=') line of
           (_, "") -> Nothing
           (key, _:value) -> Just (trim key, trim value)

trim :: String -> String
trim = dropWhileEnd isSpace . dropWhile isSpace

dropWhileEnd :: (a -> Bool) -> [a] -> [a]
dropWhileEnd predicate = reverse . dropWhile predicate . reverse
