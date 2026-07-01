module NsCDE.Runtime.Backend
  ( materializeBackdropSelection
  , detectLabwcCapabilities
  , findExecutableInPath
  , launchFailsafeTerminal
  , logoutLabwcBackend
  , runPowerAction
  , reloadLabwcBackend
  ) where

import System.Directory (copyFile, createDirectoryIfMissing, doesFileExist)
import System.Exit (ExitCode(..))
import System.FilePath ((</>), (<.>), takeExtension)
import System.Process
  ( CreateProcess(env)
  , createProcess
  , proc
  , readCreateProcessWithExitCode
  , waitForProcess
  )

import NsCDE.Domain.Backdrop (BackdropMode(..), BackdropSelection(..))
import NsCDE.Domain.Runtime (RuntimePowerAction(..))
import NsCDE.Foundation.EnvFile (KeyValue)
import NsCDE.Parse.PaletteDp (resolvePalettePath)

materializeBackdropSelection
  :: FilePath
  -> FilePath
  -> FilePath
  -> FilePath
  -> FilePath
  -> FilePath
  -> Int
  -> BackdropSelection
  -> IO Bool
materializeBackdropSelection
  homeDir
  fvwmUserDir
  dataDir
  toolsDir
  systemPath
  palettePath
  colorCount
  selection
  | backdropSelectionDesk selection <= 0 = pure False
  | null (backdropSelectionImage selection) = pure False
  | otherwise = do
      createDirectoryIfMissing True (fvwmUserDir </> "backer")
      case backdropSelectionMode selection of
        BackdropModeTiled ->
          materializeTiledBackdrop
            homeDir
            fvwmUserDir
            dataDir
            toolsDir
            systemPath
            palettePath
            colorCount
            selection
        BackdropModePhoto ->
          materializeDirectBackdrop fvwmUserDir dataDir selection
        BackdropModeAspect ->
          materializeDirectBackdrop fvwmUserDir dataDir selection
        BackdropModeUnknown _ ->
          pure False

materializeTiledBackdrop
  :: FilePath
  -> FilePath
  -> FilePath
  -> FilePath
  -> FilePath
  -> FilePath
  -> Int
  -> BackdropSelection
  -> IO Bool
materializeTiledBackdrop
  homeDir
  fvwmUserDir
  dataDir
  toolsDir
  systemPath
  palettePath
  colorCount
  selection = do
    maybePalettePath <-
      if null palettePath
        then resolvePalettePath fvwmUserDir dataDir "Charcoal"
        else pure (Just palettePath)
    maybePaletteColorgen <- resolvePaletteColorgen toolsDir systemPath
    maybeSourcePath <-
      resolveBackdropSourcePath
        fvwmUserDir
        dataDir
        selection
        ".pm"
    case (maybePalettePath, maybePaletteColorgen, maybeSourcePath) of
      (Just resolvedPalettePath, Just paletteColorgenPath, Just sourcePath) -> do
        let envVars =
              runtimeEnvironment
                homeDir
                fvwmUserDir
                dataDir
                toolsDir
                systemPath
        (exitCode, output, _) <-
          readCreateProcessWithExitCode
            ((proc paletteColorgenPath
              [ "-p", resolvedPalettePath
              , "-n", show (normalizedColorCount colorCount)
              , "-i", sourcePath
              , "-P", show (backdropColorVariant (backdropSelectionDesk selection))
              , "-b"
              ])
              { env = Just envVars
              })
            ""
        case exitCode of
          ExitSuccess -> do
            writeFile (deskBackdropOutputPath fvwmUserDir selection ".pm") output
            pngSuccess <- convertBackdropToPng systemPath fvwmUserDir selection
            pure pngSuccess
          _ ->
            pure False
      _ ->
        pure False

convertBackdropToPng :: FilePath -> FilePath -> BackdropSelection -> IO Bool
convertBackdropToPng systemPath fvwmUserDir selection = do
  maybeConvert <- findExecutableInPath systemPath "convert"
  case maybeConvert of
    Nothing ->
      pure False
    Just convertPath -> do
      let pmPath = deskBackdropOutputPath fvwmUserDir selection ".pm"
          pngPath = deskBackdropOutputPath fvwmUserDir selection ".png"
      (exitCode, _, _) <-
        readCreateProcessWithExitCode
          (proc convertPath [pmPath, pngPath])
          ""
      pure (exitCode == ExitSuccess)

materializeDirectBackdrop
  :: FilePath
  -> FilePath
  -> BackdropSelection
  -> IO Bool
materializeDirectBackdrop fvwmUserDir dataDir selection = do
  maybeSourcePath <-
    resolveBackdropSourcePath
      fvwmUserDir
      dataDir
      selection
      ".png"
  case maybeSourcePath of
    Just sourcePath -> do
      copyFile sourcePath (deskBackdropOutputPath fvwmUserDir selection ".png")
      pure True
    Nothing ->
      pure False

deskBackdropOutputPath :: FilePath -> BackdropSelection -> String -> FilePath
deskBackdropOutputPath fvwmUserDir selection extension =
  fvwmUserDir </> "backer" </>
    ("Desk" ++ show (backdropSelectionDesk selection) ++ "-" ++ backdropSelectionImage selection ++ extension)

resolveBackdropSourcePath
  :: FilePath
  -> FilePath
  -> BackdropSelection
  -> String
  -> IO (Maybe FilePath)
resolveBackdropSourcePath fvwmUserDir dataDir selection extension =
  firstExistingPath
    [ fvwmUserDir </> directoryName </> imageFileName
    , dataDir </> directoryName </> imageFileName
    ]
  where
    directoryName =
      case backdropSelectionMode selection of
        BackdropModeTiled -> "backdrops"
        BackdropModePhoto -> "photos"
        BackdropModeAspect -> "photos"
        BackdropModeUnknown _ -> "backdrops"
    imageFileName
      | takeExtension (backdropSelectionImage selection) == extension =
          backdropSelectionImage selection
      | otherwise =
          backdropSelectionImage selection <.> drop 1 extension

resolvePaletteColorgen :: FilePath -> FilePath -> IO (Maybe FilePath)
resolvePaletteColorgen toolsDir systemPath = do
  let bundledPath = toolsDir </> "palette_colorgen"
  bundledExists <- doesFileExist bundledPath
  if bundledExists
    then pure (Just bundledPath)
    else findExecutableInPath systemPath "palette_colorgen"

runtimeEnvironment
  :: FilePath
  -> FilePath
  -> FilePath
  -> FilePath
  -> FilePath
  -> [(String, String)]
runtimeEnvironment homeDir fvwmUserDir dataDir toolsDir systemPath =
  [ ("HOME", homeDir)
  , ("FVWM_USERDIR", fvwmUserDir)
  , ("NSCDE_DATADIR", dataDir)
  , ("NSCDE_TOOLSDIR", toolsDir)
  ] ++
    [ ("PATH", systemPath)
    | not (null systemPath)
    ]

normalizedColorCount :: Int -> Int
normalizedColorCount 4 = 4
normalizedColorCount _ = 8

backdropColorVariant :: Int -> Int
backdropColorVariant deskNumber =
  case normalizedDesk of
    1 -> 3
    2 -> 5
    3 -> 6
    4 -> 7
    5 -> 3
    6 -> 5
    7 -> 6
    _ -> 7
  where
    normalizedDesk
      | deskNumber <= 0 = 1
      | otherwise = ((deskNumber - 1) `mod` 8) + 1

findExecutableInPath :: FilePath -> String -> IO (Maybe FilePath)
findExecutableInPath searchPath executableName =
  firstExistingPath (candidatePaths searchPath)
  where
    candidatePaths pathValue =
      [ dir </> executableName
      | dir <- splitSearchPath pathValue
      , not (null dir)
      ]

splitSearchPath :: FilePath -> [FilePath]
splitSearchPath "" = []
splitSearchPath pathValue =
  case break (== ':') pathValue of
    (segment, ':' : rest) -> segment : splitSearchPath rest
    (segment, _) -> [segment]

firstExistingPath :: [FilePath] -> IO (Maybe FilePath)
firstExistingPath [] = pure Nothing
firstExistingPath (candidate:rest) = do
  exists <- doesFileExist candidate
  if exists
    then pure (Just candidate)
    else firstExistingPath rest

detectLabwcCapabilities :: FilePath -> FilePath -> IO [KeyValue]
detectLabwcCapabilities toolsDir systemPath = do
  powerSupport <- detectPowerCapabilities toolsDir systemPath
  pure $
    map (`pairCapability` "1")
      [ "supports-server-side-decoration-control"
      , "supports-live-theme-reload"
      , "supports-workspace-switch"
      , "supports-layer-shell"
      , "supports-foreign-toplevel"
      , "supports-system-action-dialog"
      , "supports-power-shutdown"
      , "supports-power-reboot"
      ] ++
    [ pairCapability "supports-power-suspend" "1"
    | capabilityEnabled "suspend" powerSupport
    ] ++
    [ pairCapability "supports-power-hybrid-suspend" "1"
    | capabilityEnabled "hybrid-suspend" powerSupport
    ] ++
    [ pairCapability "supports-power-hibernate" "1"
    | capabilityEnabled "hibernate" powerSupport
    ]

reloadLabwcBackend :: FilePath -> IO ()
reloadLabwcBackend systemPath = do
  maybePkill <- findExecutableInPath systemPath "pkill"
  case maybePkill of
    Just pkillPath -> do
      (_, _, _, processHandle) <- createProcess (proc pkillPath ["-HUP", "-x", "labwc"])
      _ <- waitForProcess processHandle
      pure ()
    Nothing ->
      pure ()

logoutLabwcBackend :: FilePath -> IO ()
logoutLabwcBackend systemPath = do
  maybePkill <- findExecutableInPath systemPath "pkill"
  case maybePkill of
    Just pkillPath -> do
      (_, _, _, processHandle) <- createProcess (proc pkillPath ["-TERM", "-x", "labwc"])
      _ <- waitForProcess processHandle
      pure ()
    Nothing ->
      pure ()

launchFailsafeTerminal :: FilePath -> IO Bool
launchFailsafeTerminal systemPath =
  launchFirst ["weston-terminal", "xterm", "foot", "alacritty"]
  where
    launchFirst [] = pure False
    launchFirst (candidate:rest) = do
      maybePath <- findExecutableInPath systemPath candidate
      case maybePath of
        Just executablePath -> do
          _ <- createProcess (proc executablePath [])
          pure True
        Nothing ->
          launchFirst rest

runPowerAction :: FilePath -> FilePath -> RuntimePowerAction -> IO Bool
runPowerAction toolsDir systemPath powerAction = do
  let acpimgrPath = toolsDir </> "acpimgr"
      actionText = renderPowerAction powerAction
  acpimgrExists <- doesFileExist acpimgrPath
  if not acpimgrExists
    then pure False
    else do
      (_, _, _, processHandle) <- createProcess (proc acpimgrPath [actionText])
      exitCode <- waitForProcess processHandle
      case exitCode of
        ExitSuccess -> pure True
        _ -> do
          maybeSudo <- findExecutableInPath systemPath "sudo"
          case maybeSudo of
            Just sudoPath -> do
              (_, _, _, sudoHandle) <- createProcess (proc sudoPath ["-n", acpimgrPath, actionText])
              sudoExit <- waitForProcess sudoHandle
              pure (sudoExit == ExitSuccess)
            Nothing ->
              pure False

renderPowerAction :: RuntimePowerAction -> String
renderPowerAction powerAction =
  case powerAction of
    PowerShutdown -> "poweroff"
    PowerReboot -> "reboot"
    PowerSuspend -> "suspend"
    PowerHybridSuspend -> "hybrid-suspend"
    PowerHibernate -> "hibernate"

detectPowerCapabilities :: FilePath -> FilePath -> IO [KeyValue]
detectPowerCapabilities toolsDir systemPath = do
  let acpimgrPath = toolsDir </> "acpimgr"
  acpimgrExists <- doesFileExist acpimgrPath
  if not acpimgrExists
    then pure []
    else do
      supportedActions <- detectSupportedActions acpimgrPath systemPath powerActions
      pure
        [ ("ACTION", actionText)
        | actionText <- supportedActions
        ]

detectSupportedActions :: FilePath -> FilePath -> [String] -> IO [String]
detectSupportedActions _ _ [] = pure []
detectSupportedActions acpimgrPath systemPath (actionText:rest) = do
  supported <- probePowerAction acpimgrPath systemPath actionText
  remaining <- detectSupportedActions acpimgrPath systemPath rest
  pure $
    if supported
      then actionText : remaining
      else remaining

probePowerAction :: FilePath -> FilePath -> String -> IO Bool
probePowerAction acpimgrPath systemPath actionText = do
  (_, _, _, processHandle) <- createProcess (proc acpimgrPath [actionText, "systemd"])
  exitCode <- waitForProcess processHandle
  case exitCode of
    ExitSuccess -> pure True
    _ -> do
      maybeSudo <- findExecutableInPath systemPath "sudo"
      case maybeSudo of
        Just sudoPath -> do
          (_, _, _, sudoHandle) <-
            createProcess (proc sudoPath ["-n", acpimgrPath, actionText, "systemd"])
          sudoExit <- waitForProcess sudoHandle
          pure (sudoExit == ExitSuccess)
        Nothing ->
          pure False

capabilityEnabled :: String -> [KeyValue] -> Bool
capabilityEnabled _ [] = False
capabilityEnabled actionText (("ACTION", candidate):rest)
  | actionText == candidate = True
  | otherwise = capabilityEnabled actionText rest
capabilityEnabled actionText (_:rest) =
  capabilityEnabled actionText rest

pairCapability :: String -> String -> KeyValue
pairCapability = (,)

powerActions :: [String]
powerActions =
  [ "suspend"
  , "hybrid-suspend"
  , "hibernate"
  ]
