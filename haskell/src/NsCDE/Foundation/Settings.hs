module NsCDE.Foundation.Settings
  ( lookupIntFrom
  , lookupText
  , lookupTextFrom
  , lookupValue
  ) where

import NsCDE.Foundation.EnvFile (KeyValue)

lookupValue :: [KeyValue] -> String -> Maybe String
lookupValue [] _ = Nothing
lookupValue ((candidate, value):rest) key
  | candidate == key = Just value
  | otherwise = lookupValue rest key

lookupText :: [KeyValue] -> String -> String -> String
lookupText settings key fallback =
  case lookupValue settings key of
    Just value -> value
    Nothing -> fallback

lookupTextFrom :: [KeyValue] -> [KeyValue] -> String -> String -> String
lookupTextFrom envSettings staticSettings key fallback =
  case lookupValue envSettings key of
    Just value | not (null value) -> value
    _ ->
      case lookupValue staticSettings key of
        Just value | not (null value) -> value
        _ -> fallback

lookupIntFrom :: [KeyValue] -> [KeyValue] -> String -> Int -> Int
lookupIntFrom envSettings staticSettings key fallback =
  case lookupRead envSettings key of
    Just value -> value
    Nothing ->
      case lookupRead staticSettings key of
        Just value -> value
        Nothing -> fallback

lookupRead :: [KeyValue] -> String -> Maybe Int
lookupRead settings key =
  case lookupValue settings key of
    Nothing -> Nothing
    Just value ->
      case reads value of
        [(parsed, "")] -> Just parsed
        _ -> Nothing
