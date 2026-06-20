module NsCDE.Backend.Labwc.Theme
  ( labwcThemeDir
  , renderLabwcThemeFiles
  , writeLabwcTheme
  ) where

import Control.Monad (forM_)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory)

import NsCDE.Domain.Palette
import NsCDE.Foundation.Common (writeAtomicFile)
import NsCDE.Integration.MotifColors (motifColorsFromBackground)

labwcThemeDir :: FilePath -> String -> FilePath
labwcThemeDir themesRoot themeName =
  themesRoot </> themeName </> "labwc"

renderLabwcThemeFiles :: [PaletteColor] -> [(FilePath, String)]
renderLabwcThemeFiles paletteColors =
  [ ("themerc", renderThemerc themeColors)
  , ("menu-active.xpm", renderMenuXpm (themeActiveBevelHighlight themeColors) (themeActiveBevelShadow themeColors))
  , ("menu-inactive.xpm", renderMenuXpm (themeInactiveBevelHighlight themeColors) (themeInactiveBevelShadow themeColors))
  , ("iconify-active.xpm", renderIconifyXpm (themeActiveBevelHighlight themeColors) (themeActiveBevelShadow themeColors))
  , ("iconify-inactive.xpm", renderIconifyXpm (themeInactiveBevelHighlight themeColors) (themeInactiveBevelShadow themeColors))
  , ("close.xbm", closeXbm)
  , ("max.xbm", maxXbm)
  , ("max_toggled.xbm", maxToggledXbm)
  , ("iconify.xbm", iconifyXbm)
  , ("shade.xbm", shadeXbm)
  , ("shade_toggled.xbm", shadeToggledXbm)
  , ("desk.xbm", deskXbm)
  , ("desk_toggled.xbm", deskToggledXbm)
  , ("2x/close.xbm", close2xXbm)
  , ("2x/max.xbm", max2xXbm)
  , ("2x/max_toggled.xbm", maxToggled2xXbm)
  , ("2x/iconify.xbm", iconify2xXbm)
  , ("2x/shade.xbm", shade2xXbm)
  , ("2x/shade_toggled.xbm", shadeToggled2xXbm)
  , ("2x/desk.xbm", desk2xXbm)
  , ("2x/desk_toggled.xbm", deskToggled2xXbm)
  ]
  where
    themeColors = resolveThemeColors paletteColors

writeLabwcTheme :: FilePath -> [PaletteColor] -> IO ()
writeLabwcTheme themeDir paletteColors = do
  createDirectoryIfMissing True themeDir
  forM_ (renderLabwcThemeFiles paletteColors) $ \(relativePath, contents) -> do
    let targetPath = themeDir </> relativePath
    createDirectoryIfMissing True (takeDirectory targetPath)
    writeAtomicFile targetPath contents

data LabwcThemeColors = LabwcThemeColors
  { themeActiveBorder :: String
  , themeActiveBorderTop :: String
  , themeActiveBorderBottom :: String
  , themeInactiveBorder :: String
  , themeInactiveBorderTop :: String
  , themeInactiveBorderBottom :: String
  , themeActiveTitleBg :: String
  , themeInactiveTitleBg :: String
  , themeActiveText :: String
  , themeInactiveText :: String
  , themeMenuBg :: String
  , themeMenuText :: String
  , themeMenuActiveBg :: String
  , themeMenuActiveText :: String
  , themeMenuBorder :: String
  , themeMenuSep :: String
  , themeMenuTitleBg :: String
  , themeMenuTitleText :: String
  , themeOsdBg :: String
  , themeOsdBorder :: String
  , themeOsdText :: String
  , themeActiveBevelHighlight :: String
  , themeActiveBevelShadow :: String
  , themeInactiveBevelHighlight :: String
  , themeInactiveBevelShadow :: String
  , themeButtonBg :: String
  , themeButtonHighlight :: String
  , themeButtonShadow :: String
  , themeButtonPressedBg :: String
  , themeGrooveHighlight :: String
  , themeGrooveShadow :: String
  , themeHandleHighlight :: String
  , themeHandleShadow :: String
  }

resolveThemeColors :: [PaletteColor] -> LabwcThemeColors
resolveThemeColors paletteColors =
  case (paletteColorAt 1, paletteColorAt 2, paletteColorAt 6) of
    (Just activeBg, Just inactiveBg, Just transientBg) ->
      themeColorsFromPalette activeBg inactiveBg transientBg
    _ ->
      fallbackThemeColors
  where
    paletteColorAt index =
      lookupIndex index paletteColors

lookupIndex :: Int -> [a] -> Maybe a
lookupIndex _ [] = Nothing
lookupIndex index (value:rest)
  | index <= 1 = Just value
  | otherwise = lookupIndex (index - 1) rest

themeColorsFromPalette :: PaletteColor -> PaletteColor -> PaletteColor -> LabwcThemeColors
themeColorsFromPalette activeBg inactiveBg transientBg =
  let active = motifColorsFromBackground activeBg
      inactive = motifColorsFromBackground inactiveBg
      transient = motifColorsFromBackground transientBg
      activeTitleBg = renderHexColor8 (motifBgColor active)
      activeBorderTop = renderHexColor8 (motifTsColor active)
      activeBorderBottom = renderHexColor8 (motifBsColor active)
      activeText = renderHexColor8 (motifFgColor active)
      inactiveTitleBg = renderHexColor8 (motifBgColor inactive)
      inactiveBorderTop = renderHexColor8 (motifTsColor inactive)
      inactiveBorderBottom = renderHexColor8 (motifBsColor inactive)
      inactiveText = renderHexColor8 (motifFgColor inactive)
      transientBgColor = renderHexColor8 (motifBgColor transient)
      transientBorder = renderHexColor8 (motifBsColor transient)
      transientText = renderHexColor8 (motifFgColor transient)
      inactiveSelect = renderHexColor8 (motifSelColor inactive)
  in LabwcThemeColors
      { themeActiveBorder = activeTitleBg
      , themeActiveBorderTop = activeBorderTop
      , themeActiveBorderBottom = activeBorderBottom
      , themeInactiveBorder = inactiveTitleBg
      , themeInactiveBorderTop = inactiveBorderTop
      , themeInactiveBorderBottom = inactiveBorderBottom
      , themeActiveTitleBg = activeTitleBg
      , themeInactiveTitleBg = inactiveTitleBg
      , themeActiveText = activeText
      , themeInactiveText = inactiveText
      , themeMenuBg = inactiveTitleBg
      , themeMenuText = inactiveText
      , themeMenuActiveBg = inactiveSelect
      , themeMenuActiveText = inactiveText
      , themeMenuBorder = inactiveBorderBottom
      , themeMenuSep = inactiveBorderBottom
      , themeMenuTitleBg = activeTitleBg
      , themeMenuTitleText = activeText
      , themeOsdBg = transientBgColor
      , themeOsdBorder = transientBorder
      , themeOsdText = transientText
      , themeActiveBevelHighlight = activeBorderTop
      , themeActiveBevelShadow = activeBorderBottom
      , themeInactiveBevelHighlight = inactiveBorderTop
      , themeInactiveBevelShadow = inactiveBorderBottom
      , themeButtonBg = inactiveTitleBg
      , themeButtonHighlight = inactiveBorderTop
      , themeButtonShadow = inactiveBorderBottom
      , themeButtonPressedBg = inactiveSelect
      , themeGrooveHighlight = activeBorderTop
      , themeGrooveShadow = activeBorderBottom
      , themeHandleHighlight = inactiveBorderTop
      , themeHandleShadow = inactiveBorderBottom
      }

fallbackThemeColors :: LabwcThemeColors
fallbackThemeColors =
  LabwcThemeColors
    { themeActiveBorder = "#6b7785"
    , themeActiveBorderTop = "#8a9baa"
    , themeActiveBorderBottom = "#4f5964"
    , themeInactiveBorder = "#4f5964"
    , themeInactiveBorderTop = "#6b7785"
    , themeInactiveBorderBottom = "#3a434b"
    , themeActiveTitleBg = "#355d84"
    , themeInactiveTitleBg = "#6b7785"
    , themeActiveText = "#ffffff"
    , themeInactiveText = "#e7e7e7"
    , themeMenuBg = "#b7c1ca"
    , themeMenuText = "#101010"
    , themeMenuActiveBg = "#355d84"
    , themeMenuActiveText = "#ffffff"
    , themeMenuBorder = "#4f5964"
    , themeMenuSep = "#4f5964"
    , themeMenuTitleBg = "#355d84"
    , themeMenuTitleText = "#ffffff"
    , themeOsdBg = "#b7c1ca"
    , themeOsdBorder = "#4f5964"
    , themeOsdText = "#101010"
    , themeActiveBevelHighlight = "#8a9baa"
    , themeActiveBevelShadow = "#4f5964"
    , themeInactiveBevelHighlight = "#6b7785"
    , themeInactiveBevelShadow = "#3a434b"
    , themeButtonBg = "#6b7785"
    , themeButtonHighlight = "#8a9baa"
    , themeButtonShadow = "#4f5964"
    , themeButtonPressedBg = "#4f5964"
    , themeGrooveHighlight = "#8a9baa"
    , themeGrooveShadow = "#4f5964"
    , themeHandleHighlight = "#8a9baa"
    , themeHandleShadow = "#4f5964"
    }

renderThemerc :: LabwcThemeColors -> String
renderThemerc themeColors =
  unlines
    [ "border.width: 5"
    , "window.titlebar.padding.width: 0"
    , "window.titlebar.padding.height: 0"
    , "window.active.border.color: " ++ themeActiveBorder themeColors
    , "window.active.border.color.top: " ++ themeActiveBorderTop themeColors
    , "window.active.border.color.left: " ++ themeActiveBorderTop themeColors
    , "window.active.border.color.bottom: " ++ themeActiveBorderBottom themeColors
    , "window.active.border.color.right: " ++ themeActiveBorderBottom themeColors
    , "window.active.frame.outer.width: 1"
    , "window.active.frame.inner.width: 4"
    , "window.inactive.border.color: " ++ themeInactiveBorder themeColors
    , "window.inactive.border.color.top: " ++ themeInactiveBorderTop themeColors
    , "window.inactive.border.color.left: " ++ themeInactiveBorderTop themeColors
    , "window.inactive.border.color.bottom: " ++ themeInactiveBorderBottom themeColors
    , "window.inactive.border.color.right: " ++ themeInactiveBorderBottom themeColors
    , "window.inactive.frame.outer.width: 1"
    , "window.inactive.frame.inner.width: 4"
    , "window.active.titlebar.bevel.highlight.color: " ++ themeActiveBevelHighlight themeColors
    , "window.active.titlebar.bevel.shadow.color: " ++ themeActiveBevelShadow themeColors
    , "window.active.titlebar.bevel.width: 1"
    , "window.inactive.titlebar.bevel.highlight.color: " ++ themeInactiveBevelHighlight themeColors
    , "window.inactive.titlebar.bevel.shadow.color: " ++ themeInactiveBevelShadow themeColors
    , "window.inactive.titlebar.bevel.width: 1"
    , "window.button.bg.color: " ++ themeButtonBg themeColors
    , "window.button.bg.highlight.color: " ++ themeButtonHighlight themeColors
    , "window.button.bg.shadow.color: " ++ themeButtonShadow themeColors
    , "window.button.pressed.bg.color: " ++ themeButtonPressedBg themeColors
    , "window.button.pressed.bg.highlight.color: " ++ themeButtonShadow themeColors
    , "window.button.pressed.bg.shadow.color: " ++ themeButtonHighlight themeColors
    , "window.separator.groove.width: 1"
    , "window.separator.groove.highlight.color: " ++ themeGrooveHighlight themeColors
    , "window.separator.groove.shadow.color: " ++ themeGrooveShadow themeColors
    , "window.handle.height: 5"
    , "window.handle.bevel.highlight.color: " ++ themeHandleHighlight themeColors
    , "window.handle.bevel.shadow.color: " ++ themeHandleShadow themeColors
    , "window.active.title.bg.color: " ++ themeActiveTitleBg themeColors
    , "window.inactive.title.bg.color: " ++ themeInactiveTitleBg themeColors
    , "window.*.title.bg: Solid"
    , "window.active.label.text.color: " ++ themeActiveText themeColors
    , "window.inactive.label.text.color: " ++ themeInactiveText themeColors
    , "window.label.text.justify: center"
    , "window.button.width: 16"
    , "window.button.height: 16"
    , "window.button.spacing: 0"
    , "window.button.hover.bg.color: #ffffff20"
    , "window.button.hover.bg.corner-radius: 0"
    , "window.active.button.unpressed.image.color: " ++ themeActiveText themeColors
    , "window.inactive.button.unpressed.image.color: " ++ themeInactiveText themeColors
    , "menu.border.width: 1"
    , "menu.border.color: " ++ themeMenuBorder themeColors
    , "menu.items.bg.color: " ++ themeMenuBg themeColors
    , "menu.items.text.color: " ++ themeMenuText themeColors
    , "menu.items.active.bg.color: " ++ themeMenuActiveBg themeColors
    , "menu.items.active.text.color: " ++ themeMenuActiveText themeColors
    , "menu.items.padding.x: 8"
    , "menu.items.padding.y: 4"
    , "menu.separator.width: 1"
    , "menu.separator.padding.width: 4"
    , "menu.separator.padding.height: 3"
    , "menu.separator.color: " ++ themeMenuSep themeColors
    , "menu.title.bg.color: " ++ themeMenuTitleBg themeColors
    , "menu.title.text.color: " ++ themeMenuTitleText themeColors
    , "menu.title.text.justify: Center"
    , "osd.bg.color: " ++ themeOsdBg themeColors
    , "osd.border.color: " ++ themeOsdBorder themeColors
    , "osd.border.width: 2"
    , "osd.label.text.color: " ++ themeOsdText themeColors
    , "osd.workspace-switcher.boxes.width: 24"
    , "osd.workspace-switcher.boxes.height: 18"
    , "osd.workspace-switcher.boxes.border.width: 2"
    ]

renderMenuXpm :: String -> String -> String
renderMenuXpm topColor bottomColor =
  unlines
    [ "/* XPM */"
    , "static char *menu_xpm[] = {"
    , "\"12 4 3 1\","
    , "\"  c None\","
    , "\"# c " ++ bottomColor ++ "\","
    , "\". c " ++ topColor ++ "\","
    , "\"............\","
    , "\".          #\","
    , "\".          #\","
    , "\".###########\""
    , "};"
    ]

renderIconifyXpm :: String -> String -> String
renderIconifyXpm topColor bottomColor =
  unlines
    [ "/* XPM */"
    , "static char *iconify_xpm[] = {"
    , "\"4 4 3 1\","
    , "\"  c None\","
    , "\"# c " ++ bottomColor ++ "\","
    , "\". c " ++ topColor ++ "\","
    , "\"...#\","
    , "\".  #\","
    , "\".  #\","
    , "\".###\""
    , "};"
    ]

closeXbm :: String
closeXbm =
  unlines
    [ "#define close_width 8"
    , "#define close_height 8"
    , "static unsigned char close_bits[] = {"
    , "  0x81, 0x42, 0x24, 0x18, 0x18, 0x24, 0x42, 0x81 };"
    ]

maxXbm :: String
maxXbm =
  unlines
    [ "#define max_width 8"
    , "#define max_height 8"
    , "static unsigned char max_bits[] = {"
    , "  0xff, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0xff };"
    ]

maxToggledXbm :: String
maxToggledXbm =
  unlines
    [ "#define max_toggled_width 8"
    , "#define max_toggled_height 8"
    , "static unsigned char max_toggled_bits[] = {"
    , "  0x7e, 0x42, 0x5a, 0x5a, 0x42, 0x42, 0x42, 0x7e };"
    ]

iconifyXbm :: String
iconifyXbm =
  unlines
    [ "#define iconify_width 8"
    , "#define iconify_height 8"
    , "static unsigned char iconify_bits[] = {"
    , "  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff };"
    ]

shadeXbm :: String
shadeXbm =
  unlines
    [ "#define shade_width 8"
    , "#define shade_height 8"
    , "static unsigned char shade_bits[] = {"
    , "  0xff, 0x81, 0xc3, 0xe7, 0xff, 0x00, 0x00, 0x00 };"
    ]

shadeToggledXbm :: String
shadeToggledXbm =
  unlines
    [ "#define shade_toggled_width 8"
    , "#define shade_toggled_height 8"
    , "static unsigned char shade_toggled_bits[] = {"
    , "  0x00, 0x00, 0x00, 0xff, 0xe7, 0xc3, 0x81, 0xff };"
    ]

deskXbm :: String
deskXbm =
  unlines
    [ "#define desk_width 8"
    , "#define desk_height 8"
    , "static unsigned char desk_bits[] = {"
    , "  0x3c, 0x42, 0x81, 0xa5, 0x81, 0x99, 0x42, 0x3c };"
    ]

deskToggledXbm :: String
deskToggledXbm =
  unlines
    [ "#define desk_toggled_width 8"
    , "#define desk_toggled_height 8"
    , "static unsigned char desk_toggled_bits[] = {"
    , "  0x3c, 0x7e, 0xff, 0xdb, 0xff, 0xe7, 0x7e, 0x3c };"
    ]

close2xXbm :: String
close2xXbm =
  unlines
    [ "#define close_width 16"
    , "#define close_height 16"
    , "static unsigned char close_bits[] = {"
    , "  0x03, 0xc0, 0x03, 0xc0, 0x0c, 0x30, 0x0c, 0x30,"
    , "  0x30, 0x0c, 0x30, 0x0c, 0xc0, 0x03, 0xc0, 0x03,"
    , "  0xc0, 0x03, 0xc0, 0x03, 0x30, 0x0c, 0x30, 0x0c,"
    , "  0x0c, 0x30, 0x0c, 0x30, 0x03, 0xc0, 0x03, 0xc0 };"
    ]

max2xXbm :: String
max2xXbm =
  unlines
    [ "#define max_width 16"
    , "#define max_height 16"
    , "static unsigned char max_bits[] = {"
    , "  0xff, 0xff, 0xff, 0xff, 0x03, 0xc0, 0x03, 0xc0,"
    , "  0x03, 0xc0, 0x03, 0xc0, 0x03, 0xc0, 0x03, 0xc0,"
    , "  0x03, 0xc0, 0x03, 0xc0, 0x03, 0xc0, 0x03, 0xc0,"
    , "  0x03, 0xc0, 0x03, 0xc0, 0xff, 0xff, 0xff, 0xff };"
    ]

maxToggled2xXbm :: String
maxToggled2xXbm =
  unlines
    [ "#define max_toggled_width 16"
    , "#define max_toggled_height 16"
    , "static unsigned char max_toggled_bits[] = {"
    , "  0xfc, 0x3f, 0xfc, 0x3f, 0x0c, 0x30, 0x0c, 0x30,"
    , "  0xcc, 0x33, 0xcc, 0x33, 0xcc, 0x33, 0xcc, 0x33,"
    , "  0x0c, 0x30, 0x0c, 0x30, 0x0c, 0x30, 0x0c, 0x30,"
    , "  0x0c, 0x30, 0x0c, 0x30, 0xfc, 0x3f, 0xfc, 0x3f };"
    ]

iconify2xXbm :: String
iconify2xXbm =
  unlines
    [ "#define iconify_width 16"
    , "#define iconify_height 16"
    , "static unsigned char iconify_bits[] = {"
    , "  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,"
    , "  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,"
    , "  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,"
    , "  0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };"
    ]

shade2xXbm :: String
shade2xXbm =
  unlines
    [ "#define shade_width 16"
    , "#define shade_height 16"
    , "static unsigned char shade_bits[] = {"
    , "  0xff, 0xff, 0xff, 0xff, 0x03, 0xc0, 0x03, 0xc0,"
    , "  0x0f, 0xf0, 0x0f, 0xf0, 0x3f, 0xfc, 0x3f, 0xfc,"
    , "  0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00,"
    , "  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };"
    ]

shadeToggled2xXbm :: String
shadeToggled2xXbm =
  unlines
    [ "#define shade_toggled_width 16"
    , "#define shade_toggled_height 16"
    , "static unsigned char shade_toggled_bits[] = {"
    , "  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,"
    , "  0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff,"
    , "  0x3f, 0xfc, 0x3f, 0xfc, 0x0f, 0xf0, 0x0f, 0xf0,"
    , "  0x03, 0xc0, 0x03, 0xc0, 0xff, 0xff, 0xff, 0xff };"
    ]

desk2xXbm :: String
desk2xXbm =
  unlines
    [ "#define desk_width 16"
    , "#define desk_height 16"
    , "static unsigned char desk_bits[] = {"
    , "  0xf0, 0x0f, 0xf0, 0x0f, 0x0c, 0x30, 0x0c, 0x30,"
    , "  0x03, 0xc0, 0x03, 0xc0, 0x33, 0xcc, 0x33, 0xcc,"
    , "  0x03, 0xc0, 0x03, 0xc0, 0xc3, 0xc3, 0xc3, 0xc3,"
    , "  0x0c, 0x30, 0x0c, 0x30, 0xf0, 0x0f, 0xf0, 0x0f };"
    ]

deskToggled2xXbm :: String
deskToggled2xXbm =
  unlines
    [ "#define desk_toggled_width 16"
    , "#define desk_toggled_height 16"
    , "static unsigned char desk_toggled_bits[] = {"
    , "  0xf0, 0x0f, 0xf0, 0x0f, 0xfc, 0x3f, 0xfc, 0x3f,"
    , "  0xff, 0xff, 0xff, 0xff, 0xcf, 0xf3, 0xcf, 0xf3,"
    , "  0xff, 0xff, 0xff, 0xff, 0x3f, 0xfc, 0x3f, 0xfc,"
    , "  0xfc, 0x3f, 0xfc, 0x3f, 0xf0, 0x0f, 0xf0, 0x0f };"
    ]
