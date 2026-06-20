module NsCDE.Backend.Labwc.StyleApply
  ( applyLabwcStyle
  ) where

import Control.Monad (unless, when)
import Data.Char (isSpace, toLower)
import Data.List (dropWhileEnd)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Exit (ExitCode(..))
import System.FilePath ((</>), takeDirectory)
import System.Process (CreateProcess(env), createProcess, proc, readCreateProcessWithExitCode)

import NsCDE.Backend.Labwc.RcXml (renderRcXml)
import NsCDE.Backend.Labwc.Theme (labwcThemeDir, writeLabwcTheme)
import NsCDE.Domain.Runtime (RuntimeStyleContext(..))
import NsCDE.Domain.Session (RcFont(..), RcInput(..))
import NsCDE.Domain.Style (StyleState(..))
import NsCDE.Foundation.Common (writeAtomicFile)
import NsCDE.Foundation.EnvFile (KeyValue)
import NsCDE.Parse.PaletteDp (loadPaletteColors)
import NsCDE.Parse.StyleMgrIni (lookupIniFlag)
import NsCDE.Policy.Backdrop (resolveBackdropPath)
import NsCDE.Policy.SessionPlan (buildRcConfig)

applyLabwcStyle :: RuntimeStyleContext -> FilePath -> StyleState -> IO ()
applyLabwcStyle runtimeContext palettePath styleState = do
  regenerateLabwcRc runtimeContext styleState
  regenerateLabwcTheme runtimeContext palettePath
  applyLabwcBackdrop runtimeContext styleState palettePath
  applyLabwcFonts runtimeContext styleState

applyLabwcBackdrop :: RuntimeStyleContext -> StyleState -> FilePath -> IO ()
applyLabwcBackdrop runtimeContext styleState palettePath = do
  let backdropMode = trimWhitespace (styleBackdropDesk1Mode styleState)
      backdropImage = trimWhitespace (styleBackdropDesk1Image styleState)
      backdropHelper = runtimeStyleToolsDir runtimeContext </> "nscde_labwc_bg"
  backdropPath <-
    resolveBackdropPath
      (runtimeStyleFvwmUserDir runtimeContext)
      (runtimeStyleDataDir runtimeContext)
      backdropMode
      backdropImage
  let helperEnvironment =
        runtimeBaseEnvironment runtimeContext ++
          [ ("NSCDE_PALETTE_FILE", palettePath)
          | not (null palettePath)
          ] ++
          [ ("NSCDE_BACKDROP_IMAGE", path)
          | Just path <- [backdropPath]
          ] ++
          [ ("NSCDE_BACKDROP_MODE", backdropMode)
          | not (null backdropMode) && backdropPath /= Nothing
          ]
  spawnExecutable helperEnvironment backdropHelper []

applyLabwcFonts :: RuntimeStyleContext -> StyleState -> IO ()
applyLabwcFonts runtimeContext styleState = do
  let variableFont = trimWhitespace (styleFontVariableNormalMedium styleState)
      monospacedFont = trimWhitespace (styleFontMonospacedNormalMedium styleState)
      styleIniPath = runtimeStyleFvwmUserDir runtimeContext </> "StyleMgr.ini"
      gtk2ConfigPath = runtimeEffectiveHome runtimeContext </> ".gtkrc-2.0"
      gtk3ConfigPath = runtimeStyleXdgConfigHome runtimeContext </> "gtk-3.0" </> "settings.ini"
      qt4ConfigPath = runtimeStyleXdgConfigHome runtimeContext </> "Trolltech.conf"
      qt5ConfigPath = runtimeStyleXdgConfigHome runtimeContext </> "qt5ct" </> "qt5ct.conf"
      qt6ConfigPath = runtimeStyleXdgConfigHome runtimeContext </> "qt6ct" </> "qt6ct.conf"
      xresourcesPath = runtimeStyleFvwmUserDir runtimeContext </> "Xdefaults.fontdefs"
      dunstConfigPath = runtimeStyleFvwmUserDir runtimeContext </> "Dunst.conf"
      xsettingsdConfigPath = runtimeStyleFvwmUserDir runtimeContext </> "Xsettingsd.conf"
      localFontScript = runtimeStyleFvwmUserDir runtimeContext </> "libexec" </> "fontmgr.local"

  unless (null variableFont) $ do
    integrateGtk2 <- lookupIniFlag styleIniPath "FontMgr" "integrate_gtk2"
    integrateGtk3 <- lookupIniFlag styleIniPath "FontMgr" "integrate_gtk3"
    integrateQt4 <- lookupIniFlag styleIniPath "FontMgr" "integrate_qt4"
    integrateQt5 <- lookupIniFlag styleIniPath "FontMgr" "integrate_qt5"
    integrateQt6 <- lookupIniFlag styleIniPath "FontMgr" "integrate_qt6"
    integrateXresources <- lookupIniFlag styleIniPath "FontMgr" "integrate_xresources"
    integrateLocal <- lookupIniFlag styleIniPath "FontMgr" "integrate_local"

    gtkFont <- fmap (fmap trimWhitespace) $
      runToolOutput runtimeContext "fontmgr" ["-T", variableFont]
    qtFont <- fmap (fmap trimWhitespace) $
      runToolOutput runtimeContext "fontmgr" ["-Q", variableFont]
    qtMonospaceFont <-
      if null monospacedFont
        then pure Nothing
        else fmap (fmap trimWhitespace) $
          runToolOutput runtimeContext "fontmgr" ["-Q", monospacedFont]

    when (integrateGtk2 && hasValue gtkFont) $
      runTool runtimeContext "confset"
        [ "-t", "properties"
        , "-c", gtk2ConfigPath
        , "-k", "gtk-font-name"
        , "-v", unwrapValue gtkFont
        ]

    when (integrateGtk3 && hasValue gtkFont) $ do
      createDirectoryIfMissing True (runtimeStyleXdgConfigHome runtimeContext </> "gtk-3.0")
      runTool runtimeContext "confset"
        [ "-t", "ini"
        , "-c", gtk3ConfigPath
        , "-s", "Settings"
        , "-k", "gtk-font-name"
        , "-v", unwrapValue gtkFont
        ]

    when (integrateQt4 && hasValue qtFont) $
      runTool runtimeContext "confset"
        [ "-t", "ini"
        , "-c", qt4ConfigPath
        , "-s", "Qt"
        , "-k", "font"
        , "-v", unwrapValue qtFont
        ]

    when (integrateQt5 && hasValue qtFont) $ do
      createDirectoryIfMissing True (runtimeStyleXdgConfigHome runtimeContext </> "qt5ct")
      runTool runtimeContext "confset"
        [ "-t", "ini"
        , "-c", qt5ConfigPath
        , "-s", "Fonts"
        , "-k", "general"
        , "-v", unwrapValue qtFont
        ]
      when (hasValue qtMonospaceFont) $
        runTool runtimeContext "confset"
          [ "-t", "ini"
          , "-c", qt5ConfigPath
          , "-s", "Fonts"
          , "-k", "fixed"
          , "-v", unwrapValue qtMonospaceFont
          ]

    qt6ConfigExists <- doesFileExist qt6ConfigPath
    when (integrateQt6 && qt6ConfigExists && hasValue qtFont) $ do
      runTool runtimeContext "confset"
        [ "-t", "ini"
        , "-c", qt6ConfigPath
        , "-s", "Fonts"
        , "-k", "general"
        , "-v", unwrapValue qtFont
        ]
      when (hasValue qtMonospaceFont) $
        runTool runtimeContext "confset"
          [ "-t", "ini"
          , "-c", qt6ConfigPath
          , "-s", "Fonts"
          , "-k", "fixed"
          , "-v", unwrapValue qtMonospaceFont
          ]

    fontsetPath <- resolveFontsetPath runtimeContext styleState
    when integrateXresources $
      case fontsetPath of
        Just path -> do
          maybeFontDefs <- runToolOutput runtimeContext "fontmgr" ["-X", path]
          case maybeFontDefs of
            Just fontDefs -> do
              createDirectoryIfMissing True (runtimeStyleFvwmUserDir runtimeContext)
              writeAtomicFile xresourcesPath fontDefs
            Nothing -> pure ()
          dunstConfigExists <- doesFileExist dunstConfigPath
          when (dunstConfigExists && hasValue gtkFont) $
            runTool runtimeContext "confset"
              [ "-t", "ini"
              , "-c", dunstConfigPath
              , "-s", "global"
              , "-k", "font"
              , "-v", unwrapValue gtkFont
              ]
        Nothing -> pure ()

    xsettingsdExists <- doesFileExist xsettingsdConfigPath
    when (xsettingsdExists && hasValue gtkFont) $
      updateXsettingsdFont xsettingsdConfigPath (unwrapValue gtkFont)

    when integrateLocal $
      case fontsetPath of
        Just path -> spawnExecutable (runtimeBaseEnvironment runtimeContext) localFontScript [path]
        Nothing -> pure ()

regenerateLabwcTheme :: RuntimeStyleContext -> FilePath -> IO ()
regenerateLabwcTheme runtimeContext palettePath = do
  let themeDir =
        labwcThemeDir
          (runtimeStyleXdgDataHome runtimeContext </> "themes")
          (runtimeStyleThemeName runtimeContext)
  paletteColors <- loadPaletteColors palettePath
  writeLabwcTheme themeDir paletteColors

regenerateLabwcRc :: RuntimeStyleContext -> StyleState -> IO ()
regenerateLabwcRc runtimeContext styleState = do
  let configDir = runtimeStyleLabwcConfigDir runtimeContext
  unless (null configDir) $ do
    createDirectoryIfMissing True configDir
    keybindXml <- readOptionalFile (runtimeStyleLabwcKeybindXmlFile runtimeContext)
    titleFont <- resolveLabwcTitleFont runtimeContext
    let rcInput =
          RcInput
            { rcInputThemeName = runtimeStyleThemeName runtimeContext
            , rcInputTitleFont = titleFont
            , rcInputWorkspaces = runtimeStyleWorkspaces runtimeContext
            , rcInputKeybindXml = keybindXml
            }
    writeAtomicFile
      (configDir </> "rc.xml")
      (renderRcXml (buildRcConfig rcInput styleState))

runtimeBaseEnvironment :: RuntimeStyleContext -> [KeyValue]
runtimeBaseEnvironment runtimeContext =
  [ ("HOME", runtimeEffectiveHome runtimeContext)
  , ("XDG_CONFIG_HOME", runtimeStyleXdgConfigHome runtimeContext)
  , ("XDG_CACHE_HOME", runtimeStyleXdgCacheHome runtimeContext)
  , ("XDG_DATA_HOME", runtimeStyleXdgDataHome runtimeContext)
  , ("NSCDE_BACKEND", runtimeStyleBackendName runtimeContext)
  , ("NSCDE_ROOT", runtimeStyleRootDir runtimeContext)
  , ("NSCDE_TOOLSDIR", runtimeStyleToolsDir runtimeContext)
  , ("NSCDE_DATADIR", runtimeStyleDataDir runtimeContext)
  , ("FVWM_USERDIR", runtimeStyleFvwmUserDir runtimeContext)
  , ("NSCDE_LABWC_THEME_NAME", runtimeStyleThemeName runtimeContext)
  , ("NSCDE_THEME_NAME", runtimeStyleThemeName runtimeContext)
  , ("NSCDE_LABWC_CONFIG_DIR", runtimeStyleLabwcConfigDir runtimeContext)
  , ("NSCDE_STATE_DIR", runtimeStyleStateDir runtimeContext)
  ] ++
    [ ("PATH", runtimeStyleSystemPath runtimeContext)
    | not (null (runtimeStyleSystemPath runtimeContext))
    ] ++
    [ ("WAYLAND_DISPLAY", runtimeStyleWaylandDisplay runtimeContext)
    | not (null (runtimeStyleWaylandDisplay runtimeContext))
    ] ++
    [ ("DISPLAY", runtimeStyleDisplayName runtimeContext)
    | not (null (runtimeStyleDisplayName runtimeContext))
    ] ++
    [ ("XDG_RUNTIME_DIR", runtimeStyleXdgRuntimeDir runtimeContext)
    | not (null (runtimeStyleXdgRuntimeDir runtimeContext))
    ]

runtimeEffectiveHome :: RuntimeStyleContext -> FilePath
runtimeEffectiveHome runtimeContext
  | null (runtimeStyleHomeDir runtimeContext) =
      takeDirectory (runtimeStyleFvwmUserDir runtimeContext)
  | otherwise = runtimeStyleHomeDir runtimeContext

readOptionalFile :: FilePath -> IO String
readOptionalFile "" = pure ""
readOptionalFile path = do
  pathExists <- doesFileExist path
  if pathExists
    then readFile path
    else pure ""

runToolOutput :: RuntimeStyleContext -> String -> [String] -> IO (Maybe String)
runToolOutput runtimeContext toolName =
  runExecutableOutput
    (runtimeBaseEnvironment runtimeContext)
    (runtimeStyleToolsDir runtimeContext </> toolName)

runTool :: RuntimeStyleContext -> String -> [String] -> IO ()
runTool runtimeContext toolName arguments = do
  _ <- runToolOutput runtimeContext toolName arguments
  pure ()

runExecutableOutput :: [KeyValue] -> FilePath -> [String] -> IO (Maybe String)
runExecutableOutput commandEnv executable arguments = do
  executableExists <- doesFileExist executable
  if not executableExists
    then pure Nothing
    else do
      (exitCode, stdout, _) <-
        readCreateProcessWithExitCode
          (proc executable arguments)
            { env = Just commandEnv
            }
          ""
      pure $
        case exitCode of
          ExitSuccess -> Just stdout
          ExitFailure _ -> Nothing

spawnExecutable :: [KeyValue] -> FilePath -> [String] -> IO ()
spawnExecutable commandEnv executable arguments = do
  executableExists <- doesFileExist executable
  when executableExists $ do
    _ <-
      createProcess
        (proc executable arguments)
          { env = Just commandEnv
          }
    pure ()

resolveFontsetPath :: RuntimeStyleContext -> StyleState -> IO (Maybe FilePath)
resolveFontsetPath runtimeContext styleState = do
  let fontsetName = trimWhitespace (styleFontsetName styleState)
      userFontsetPath = runtimeStyleFvwmUserDir runtimeContext </> "fontsets" </> (fontsetName ++ ".fontset")
      dataFontsetPath = runtimeStyleDataDir runtimeContext </> "fontsets" </> (fontsetName ++ ".fontset")
  if null fontsetName
    then pure Nothing
    else do
      userFontsetExists <- doesFileExist userFontsetPath
      if userFontsetExists
        then pure (Just userFontsetPath)
        else do
          dataFontsetExists <- doesFileExist dataFontsetPath
          pure $
            if dataFontsetExists
              then Just dataFontsetPath
              else Nothing

updateXsettingsdFont :: FilePath -> String -> IO ()
updateXsettingsdFont configPath gtkFont = do
  contents <- readFile configPath
  let updatedContents = unlines (map rewriteLine (lines contents))
  when (updatedContents /= contents) $
    writeAtomicFile configPath updatedContents
  where
    rewriteLine line
      | startsWithText "Gtk/FontName" (trimWhitespace line) =
          "Gtk/FontName \"" ++ gtkFont ++ "\""
      | otherwise = line

trimWhitespace :: String -> String
trimWhitespace =
  dropWhileEnd isSpace . dropWhile isSpace

hasValue :: Maybe String -> Bool
hasValue =
  maybe False (not . null)

unwrapValue :: Maybe String -> String
unwrapValue =
  maybe "" id

resolveLabwcTitleFont :: RuntimeStyleContext -> IO RcFont
resolveLabwcTitleFont runtimeContext = do
  maybeTitleSpec <- fmap (fmap trimWhitespace) $
    runToolOutput runtimeContext "getfont" ["-v", "-t", "bold", "-s", "large"]
  pure $
    case maybeTitleSpec >>= parseTitleFontSpec of
      Just titleFont -> titleFont
      Nothing -> fallbackTitleFont runtimeContext

fallbackTitleFont :: RuntimeStyleContext -> RcFont
fallbackTitleFont runtimeContext =
  RcFont
    { rcFontPlace = ""
    , rcFontName = runtimeStyleTitleFontName runtimeContext
    , rcFontSize = runtimeStyleTitleFontSize runtimeContext
    , rcFontSlant = runtimeStyleTitleFontSlant runtimeContext
    , rcFontWeight = runtimeStyleTitleFontWeight runtimeContext
    }

parseTitleFontSpec :: String -> Maybe RcFont
parseTitleFontSpec rawSpec =
  case stripPrefix "xft:" (trimWhitespace rawSpec) of
    Just fontBody ->
      let fontName = titleFontNameFromBody fontBody
          fontSize = lookupSizeToken (splitOn ':' fontBody)
          fontSlant =
            if containsToken "oblique" fontBody
              then "oblique"
              else if containsToken "italic" fontBody
                then "italic"
                else "normal"
      in if null fontName
           then Nothing
           else Just
             RcFont
               { rcFontPlace = ""
               , rcFontName = fontName
               , rcFontSize =
                   case fontSize of
                     Just value -> value
                     Nothing -> "10"
               , rcFontSlant = fontSlant
               , rcFontWeight = "bold"
               }
    Nothing -> Nothing

titleFontNameFromBody :: String -> String
titleFontNameFromBody fontBody =
  joinWith ":" (takeWhile keepTitleToken (splitOn ':' fontBody))
  where
    keepTitleToken token =
      let lowered = map toLower token
      in not (null token) &&
         not ("size=" `startsWithText` lowered) &&
         lowered `notElem`
           [ "thin"
           , "ultralight"
           , "light"
           , "semilight"
           , "book"
           , "normal"
           , "medium"
           , "semibold"
           , "bold"
           , "ultrabold"
           , "heavy"
           , "ultraheavy"
           , "italic"
           , "oblique"
           , "roman"
           , "regular"
           ]

lookupSizeToken :: [String] -> Maybe String
lookupSizeToken [] = Nothing
lookupSizeToken (token:rest) =
  case stripPrefix "size=" token of
    Just sizeValue ->
      let trimmedValue = trimWhitespace sizeValue
      in if null trimmedValue
           then lookupSizeToken rest
           else Just trimmedValue
    Nothing -> lookupSizeToken rest

containsToken :: String -> String -> Bool
containsToken needle =
  any ((== needle) . map toLower) . splitOn ':'

splitOn :: Eq a => a -> [a] -> [[a]]
splitOn delimiter value =
  case break (== delimiter) value of
    (left, []) -> [left]
    (left, _:right) -> left : splitOn delimiter right

joinWith :: [a] -> [[a]] -> [a]
joinWith _ [] = []
joinWith _ [value] = value
joinWith delimiter (value:rest) =
  value ++ delimiter ++ joinWith delimiter rest

stripPrefix :: Eq a => [a] -> [a] -> Maybe [a]
stripPrefix [] value = Just value
stripPrefix _ [] = Nothing
stripPrefix (prefixValue:prefixRest) (value:valueRest)
  | prefixValue == value = stripPrefix prefixRest valueRest
  | otherwise = Nothing

startsWithText :: Eq a => [a] -> [a] -> Bool
startsWithText [] _ = True
startsWithText _ [] = False
startsWithText (left:leftRest) (right:rightRest) =
  left == right && startsWithText leftRest rightRest
