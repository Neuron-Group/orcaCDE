module NsCDE.Backend.Labwc.RcXml
  ( renderRcXml
  ) where

import NsCDE.Domain.Session
import NsCDE.Foundation.Common (ensureTrailingNewline, escapeXml)

renderRcXml :: RcConfig -> String
renderRcXml config =
  concat
    [ "<?xml version=\"1.0\"?>\n"
    , "<labwc_config>\n"
    , "  <core>\n"
    , "    <decoration>server</decoration>\n"
    , "    <gap>0</gap>\n"
    , "  </core>\n"
    , "  <focus>\n"
    , "    <followMouse>" ++ escapeXml (rcFollowMouse config) ++ "</followMouse>\n"
    , "    <raiseOnFocus>" ++ escapeXml (rcRaiseOnFocus config) ++ "</raiseOnFocus>\n"
    , "  </focus>\n"
    , "  <theme>\n"
    , "    <name>" ++ escapeXml (rcThemeName config) ++ "</name>\n"
    , "    <cornerRadius>0</cornerRadius>\n"
    , "    <titlebar>\n"
    , "      <layout>menu:iconify,max</layout>\n"
    , "    </titlebar>\n"
    , concatMap renderWindowFont (rcFonts config)
    , "  </theme>\n"
    , "  <desktops>\n"
    , "    <number>" ++ show (length (rcWorkspaces config)) ++ "</number>\n"
    , "    <names>\n"
    , concatMap renderWorkspaceName (rcWorkspaces config)
    , "    </names>\n"
    , "  </desktops>\n"
    , renderKeybindXml (rcKeybindXml config)
    , "  <mouse>\n"
    , "    <default />\n"
    , "    <doubleClickTime>500</doubleClickTime>\n"
    , "    <context name=\"Root\">\n"
    , "      <mousebind button=\"Left\" action=\"Press\">\n"
    , "        <action name=\"ShowMenu\" menu=\"root-menu\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind button=\"Right\" action=\"Press\">\n"
    , "        <action name=\"ShowMenu\" menu=\"root-menu\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind direction=\"Up\" action=\"Scroll\">\n"
    , "        <action name=\"GoToDesktop\" to=\"left\" wrap=\"yes\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind direction=\"Down\" action=\"Scroll\">\n"
    , "        <action name=\"GoToDesktop\" to=\"right\" wrap=\"yes\" />\n"
    , "      </mousebind>\n"
    , "    </context>\n"
    , "    <context name=\"TitleBar\">\n"
    , "      <mousebind button=\"Left\" action=\"Press\">\n"
    , "        <action name=\"Focus\" />\n"
    , "        <action name=\"Raise\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind button=\"Right\" action=\"Click\">\n"
    , "        <action name=\"Focus\" />\n"
    , "        <action name=\"Raise\" />\n"
    , "        <action name=\"ShowMenu\" menu=\"client-menu\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind direction=\"Up\" action=\"Scroll\">\n"
    , "        <action name=\"Unshade\" />\n"
    , "        <action name=\"Focus\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind direction=\"Down\" action=\"Scroll\">\n"
    , "        <action name=\"Shade\" />\n"
    , "      </mousebind>\n"
    , "    </context>\n"
    , "    <context name=\"Title\">\n"
    , "      <mousebind button=\"Left\" action=\"Drag\">\n"
    , "        <action name=\"Move\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind button=\"Left\" action=\"DoubleClick\">\n"
    , "        <action name=\"ToggleMaximize\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind button=\"Right\" action=\"Click\">\n"
    , "        <action name=\"ShowMenu\" menu=\"client-menu\" />\n"
    , "      </mousebind>\n"
    , "    </context>\n"
    , "  </mouse>\n"
    , "</labwc_config>\n"
    ]

renderWindowFont :: RcFont -> String
renderWindowFont fontValue =
  concat
    [ "    <font place=\"" ++ rcFontPlace fontValue ++ "\">\n"
    , "      <name>" ++ escapeXml (rcFontName fontValue) ++ "</name>\n"
    , "      <size>" ++ escapeXml (rcFontSize fontValue) ++ "</size>\n"
    , "      <slant>" ++ escapeXml (rcFontSlant fontValue) ++ "</slant>\n"
    , "      <weight>" ++ escapeXml (rcFontWeight fontValue) ++ "</weight>\n"
    , "    </font>\n"
    ]

renderWorkspaceName :: String -> String
renderWorkspaceName workspace =
  "      <name>" ++ escapeXml workspace ++ "</name>\n"

renderKeybindXml :: String -> String
renderKeybindXml keybindXml =
  ensureTrailingNewline keybindXml
