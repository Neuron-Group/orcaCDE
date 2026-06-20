module NsCDE.Parse.StyleMgrIni
  ( lookupIniFlag
  , lookupIniValue
  , lookupIniValueInContents
  ) where

import Data.Char (isSpace, toLower)
import System.Directory (doesFileExist)

lookupIniFlag :: FilePath -> String -> String -> IO Bool
lookupIniFlag path sectionName keyName = do
  maybeValue <- lookupIniValue path sectionName keyName
  pure $
    case fmap (map toLower . trimWhitespace) maybeValue of
      Just "1" -> True
      Just "true" -> True
      Just "yes" -> True
      Just "on" -> True
      _ -> False

lookupIniValue :: FilePath -> String -> String -> IO (Maybe String)
lookupIniValue path sectionName keyName = do
  fileExists <- doesFileExist path
  if not fileExists
    then pure Nothing
    else do
      contents <- readFile path
      pure (lookupIniValueInContents sectionName keyName contents)

lookupIniValueInContents :: String -> String -> String -> Maybe String
lookupIniValueInContents sectionName keyName =
  search ""
    . lines
  where
    search _ [] = Nothing
    search currentSection (rawLine:rest) =
      let line = trimWhitespace rawLine
      in if null line || startsWith "#" line || startsWith ";" line
           then search currentSection rest
           else case parseSectionHeader line of
             Just nextSection ->
               search nextSection rest
             Nothing ->
               case splitOnce '=' line of
                 Just (rawKey, rawValue)
                   | currentSection == sectionName &&
                       trimWhitespace rawKey == keyName ->
                       Just (unquote (trimWhitespace rawValue))
                 _ ->
                   search currentSection rest

parseSectionHeader :: String -> Maybe String
parseSectionHeader ('[':rest) =
  case reverse rest of
    ']':revSectionName -> Just (trimWhitespace (reverse revSectionName))
    _ -> Nothing
parseSectionHeader _ = Nothing

splitOnce :: Eq a => a -> [a] -> Maybe ([a], [a])
splitOnce delimiter value =
  case break (== delimiter) value of
    (_, []) -> Nothing
    (left, _:right) -> Just (left, right)

trimWhitespace :: String -> String
trimWhitespace =
  dropWhileEnd isSpace . dropWhile isSpace

unquote :: String -> String
unquote ('"':rest) =
  case reverse rest of
    '"':revInner -> reverse revInner
    _ -> '"' : rest
unquote value = value

startsWith :: Eq a => [a] -> [a] -> Bool
startsWith [] _ = True
startsWith _ [] = False
startsWith (left:leftRest) (right:rightRest) =
  left == right && startsWith leftRest rightRest

dropWhileEnd :: (a -> Bool) -> [a] -> [a]
dropWhileEnd predicate =
  reverse . dropWhile predicate . reverse
