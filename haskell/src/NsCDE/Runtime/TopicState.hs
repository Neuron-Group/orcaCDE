module NsCDE.Runtime.TopicState
  ( changedStyleTopics
  , changedWorkspaceTopics
  , deriveTaskEntries
  , initialWindowsEntries
  , lookupEntry
  , normalizeWindowsEntries
  , normalizeWorkspaceEntries
  , producerTopicsAllowed
  , publishedWorkspaceNames
  , resolvePublishedCurrentWorkspace
  ) where

import NsCDE.Domain.Runtime
import NsCDE.Domain.Style (StyleState)
import NsCDE.Foundation.Common (splitCommaList)
import NsCDE.Foundation.EnvFile (KeyValue, parseEnvContents, renderEnvFile)

changedWorkspaceTopics :: [RuntimeTopic]
changedWorkspaceTopics =
  [ TopicPanel
  , TopicWorkspaces
  , TopicBackdrops
  , TopicPager
  ]

changedStyleTopics
  :: String
  -> String
  -> [KeyValue]
  -> [KeyValue]
  -> [KeyValue]
  -> [KeyValue]
  -> String
  -> String
  -> StyleState
  -> StyleState
  -> [RuntimeTopic]
changedStyleTopics previousFpVariant updatedFpVariant previousPalette updatedPalette previousBackdrops updatedBackdrops previousWorkspace updatedWorkspace previousStyle updatedStyle =
  TopicStyle :
    [ TopicPanel
    | previousFpVariant /= updatedFpVariant
        || previousPalette /= updatedPalette
    ]
    ++
    [ TopicBackdrops
    | previousWorkspace /= updatedWorkspace
        || previousStyle /= updatedStyle
        || previousPalette /= updatedPalette
        || previousBackdrops /= updatedBackdrops
    ]

producerTopicsAllowed :: RuntimeProducerRole -> [RuntimeTopic]
producerTopicsAllowed producerRole =
  case producerRole of
    ProducerPager -> [TopicWorkspaces, TopicPager]
    ProducerToplevel -> [TopicWindows]

normalizeWindowsEntries :: [KeyValue] -> [KeyValue]
normalizeWindowsEntries entries =
  let parsedEntries = parseEnvContents (renderEnvFile entries)
  in if null parsedEntries then initialWindowsEntries else parsedEntries

deriveTaskEntries :: FilePath -> [KeyValue] -> [KeyValue]
deriveTaskEntries commandFifo windowsEntries =
  [ ("NSCDE_TASK_COUNT", lookupEntry "NSCDE_WINDOW_COUNT" "0" windowsEntries)
  , ("NSCDE_TASK_FOCUSED", lookupEntry "NSCDE_FOCUSED_WINDOW" "" windowsEntries)
  , ("NSCDE_TASK_COMMAND_FIFO", commandFifo)
  ]

normalizeWorkspaceEntries :: [KeyValue] -> [KeyValue]
normalizeWorkspaceEntries entries =
  let parsedEntries = parseEnvContents (renderEnvFile entries)
  in if null parsedEntries then [] else parsedEntries

publishedWorkspaceNames :: [KeyValue] -> [String]
publishedWorkspaceNames entries =
  case splitCommaList (lookupEntry "NSCDE_WORKSPACES" "" entries) of
    [] -> splitCommaList (lookupEntry "NSCDE_PAGER_WORKSPACES" "" entries)
    names -> names

resolvePublishedCurrentWorkspace :: [KeyValue] -> [String] -> String -> String
resolvePublishedCurrentWorkspace entries workspaceNames fallbackCurrent
  | null workspaceNames = fallbackCurrent
  | requestedCurrent `elem` workspaceNames = requestedCurrent
  | fallbackCurrent `elem` workspaceNames = fallbackCurrent
  | otherwise =
      case workspaceNames of
        firstWorkspace:_ -> firstWorkspace
        [] -> fallbackCurrent
  where
    requestedCurrent =
      firstNonEmpty
        [ lookupEntry "NSCDE_CURRENT_WORKSPACE" "" entries
        , lookupEntry "NSCDE_PAGER_CURRENT" "" entries
        ]

firstNonEmpty :: [String] -> String
firstNonEmpty [] = ""
firstNonEmpty (candidate:rest)
  | null candidate = firstNonEmpty rest
  | otherwise = candidate

lookupEntry :: String -> String -> [KeyValue] -> String
lookupEntry _ fallback [] = fallback
lookupEntry key fallback ((candidateKey, value):rest)
  | key == candidateKey = value
  | otherwise = lookupEntry key fallback rest

initialWindowsEntries :: [KeyValue]
initialWindowsEntries =
  [ ("NSCDE_WINDOW_COUNT", "0")
  , ("NSCDE_FOCUSED_WINDOW", "")
  ]
