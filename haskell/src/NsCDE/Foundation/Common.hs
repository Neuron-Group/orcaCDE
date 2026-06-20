module NsCDE.Foundation.Common
  ( ensureTrailingNewline
  , escapeXml
  , shellQuote
  , splitCommaList
  , splitOnComma
  , trim
  , writeAtomicFile
  ) where

import Data.Char (isSpace)
import System.Directory (renameFile)

ensureTrailingNewline :: String -> String
ensureTrailingNewline "" = ""
ensureTrailingNewline value
  | last value == '\n' = value
  | otherwise = value ++ "\n"

escapeXml :: String -> String
escapeXml =
  concatMap escapeChar
  where
    escapeChar '&' = "&amp;"
    escapeChar '<' = "&lt;"
    escapeChar '>' = "&gt;"
    escapeChar '"' = "&quot;"
    escapeChar '\'' = "&apos;"
    escapeChar ch = [ch]

shellQuote :: String -> String
shellQuote value =
  "'" ++ concatMap escapeChar value ++ "'"
  where
    escapeChar '\'' = "'\"'\"'"
    escapeChar ch = [ch]

splitCommaList :: String -> [String]
splitCommaList raw =
  filter (not . null) (map trim (splitOnComma raw))

splitOnComma :: String -> [String]
splitOnComma [] = [""]
splitOnComma (',':rest) = "" : splitOnComma rest
splitOnComma (char:rest) =
  case splitOnComma rest of
    [] -> [[char]]
    token:tokens -> (char : token) : tokens

trim :: String -> String
trim = dropWhileEnd isSpace . dropWhile isSpace

writeAtomicFile :: FilePath -> String -> IO ()
writeAtomicFile path contents = do
  let tmpPath = path ++ ".tmp"
  writeFile tmpPath contents
  renameFile tmpPath path

dropWhileEnd :: (a -> Bool) -> [a] -> [a]
dropWhileEnd predicate = reverse . dropWhile predicate . reverse
