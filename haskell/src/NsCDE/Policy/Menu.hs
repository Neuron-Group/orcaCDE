module NsCDE.Policy.Menu
  ( buildMenuModel
  , mapAppMenuAction
  ) where

import System.FilePath ((</>))

import NsCDE.Domain.Menu
import NsCDE.Foundation.Common (shellQuote, splitCommaList)
import NsCDE.Foundation.EnvFile (KeyValue)
import NsCDE.Foundation.Settings (lookupText)

buildMenuModel :: [KeyValue] -> String -> [AppMenuEntry] -> Menu
buildMenuModel env terminal appEntries =
  Menu
    { menuId = "root-menu"
    , menuLabel = "NsCDE"
    , menuElements =
        [ MenuItem "Terminal" [Execute terminal]
        , MenuSeparator (Just "Style")
        , MenuItem "Style Manager" [Execute (renderWaylandQtCommand (toolsDir </> "nscde_labwc_stylemgr"))]
        , MenuSubmenu (buildStyleManagersMenu toolsDir)
        , MenuSeparator (Just "Applications")
        ]
        ++ renderApplicationMenu appEntries terminal
        ++ [ MenuSeparator (Just "Workspaces") ]
        ++ renderWorkspaceMenu workspaces
        ++ [ MenuSeparator (Just "Session")
           , MenuItem "System Action..." [Execute (renderWaylandQtCommand (toolsDir </> "nscde_labwc_sysaction"))]
           , MenuItem "Reconfigure labwc" [Reconfigure]
           , MenuItem "Exit labwc" [Exit]
           ]
    }
  where
    toolsDir = lookupText env "NSCDE_TOOLSDIR" ""
    workspaces = resolveWorkspaces env

buildStyleManagersMenu :: FilePath -> Menu
buildStyleManagersMenu toolsDir =
  Menu
    { menuId = "style-managers-menu"
    , menuLabel = "Style Managers"
    , menuElements =
        concatMap renderStyleManagerItem styleManagers
        ++ [ MenuSeparator Nothing
           , MenuItem "Icon Box" [Execute (renderWaylandQtCommand (toolsDir </> "nscde_labwc_iconbox"))]
           , MenuItem "System Information" [Execute (renderWaylandQtCommand (toolsDir </> "nscde_labwc_sysinfo"))]
           , MenuSeparator Nothing
           , MenuItem "System Action..." [Execute (renderWaylandQtCommand (toolsDir </> "nscde_labwc_sysaction"))]
           ]
    }
  where
    styleManagers =
      [ ("Color Manager", "nscde_labwc_colormgr")
      , ("Font Manager", "nscde_labwc_fontmgr")
      , ("Backdrop Manager", "nscde_labwc_backdropmgr")
      , ("Window Manager", "nscde_labwc_windowmgr")
      , ("Workspace Manager", "nscde_labwc_wsm")
      ]
    renderStyleManagerItem (label, executable) =
      [MenuItem label [Execute (renderWaylandQtCommand (toolsDir </> executable))]]

renderApplicationMenu :: [AppMenuEntry] -> String -> [MenuElement]
renderApplicationMenu appEntries terminal =
  snd (foldl appendMenuItem ("", []) appEntries)
  where
    appendMenuItem (previousClass, rendered) entry =
      case mapAppMenuAction terminal (appMenuAction entry) of
        Nothing -> (previousClass, rendered)
        Just command ->
          let separator =
                if null previousClass || previousClass == appMenuClass entry
                  then []
                  else [MenuSeparator Nothing]
              item =
                MenuItem (appMenuDisplayLabel entry) [Execute command]
          in (appMenuClass entry, rendered ++ separator ++ [item])

mapAppMenuAction :: String -> String -> Maybe String
mapAppMenuAction terminal action
  | action == "f_WideTerm" = Just terminal
  | "Exec exec " `isPrefixOf` action = Just (trimQuoted (drop (length ("Exec exec " :: String)) action))
  | "Module FvwmScript " `isPrefixOf` action = Nothing
  | "f_ToggleFvwmModule FvwmScript " `isPrefixOf` action = Nothing
  | "f_ToggleFvwmFunc " `isPrefixOf` action = Nothing
  | "f_ToggleExecWindow " `isPrefixOf` action = Nothing
  | "f_FvwmLogMgmt " `isPrefixOf` action = Nothing
  | otherwise = Nothing

renderWorkspaceMenu :: [String] -> [MenuElement]
renderWorkspaceMenu workspaces =
  map renderWorkspaceItem (zip [1 :: Int ..] workspaces)
  where
    renderWorkspaceItem (index, name) =
      MenuItem ("Workspace " ++ name) [GoToDesktop index]

renderWaylandQtCommand :: FilePath -> String
renderWaylandQtCommand target =
  "sh -c " ++ shellQuote ("QT_QPA_PLATFORM=wayland " ++ target)

resolveWorkspaces :: [KeyValue] -> [String]
resolveWorkspaces env =
  case splitCommaList workspaceText of
    [] -> ["One", "Two", "Three", "Four"]
    names -> names
  where
    workspaceText = lookupText env "NSCDE_WORKSPACES" (lookupText env "NSCDE_LABWC_WORKSPACES" "")

trimQuoted :: String -> String
trimQuoted value =
  case dropWhile (== ' ') value of
    '"':rest ->
      case reverse rest of
        '"':remaining -> reverse remaining
        _ -> '"' : rest
    trimmedValue -> trimmedValue

isPrefixOf :: Eq a => [a] -> [a] -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (left:leftRest) (right:rightRest) =
  left == right && isPrefixOf leftRest rightRest
