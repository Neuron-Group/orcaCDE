module NsCDE.Backend.Labwc.MenuXml
  ( renderMenuXml
  ) where

import NsCDE.Domain.Menu
import NsCDE.Foundation.Common (escapeXml)

renderMenuXml :: Menu -> String
renderMenuXml menu =
  unlines $
    [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    , "<openbox_menu xmlns=\"http://openbox.org/3.4/menu\">"
    ]
    ++ renderMenu 2 menu
    ++ ["</openbox_menu>"]

renderMenu :: Int -> Menu -> [String]
renderMenu indentLevel menu =
  [ indent indentLevel ++ "<menu id=\"" ++ escapeXml (menuId menu) ++ "\" label=\"" ++ escapeXml (menuLabel menu) ++ "\">"
  ]
  ++ concatMap (renderElement (indentLevel + 2)) (menuElements menu)
  ++ [indent indentLevel ++ "</menu>"]

renderElement :: Int -> MenuElement -> [String]
renderElement indentLevel element =
  case element of
    MenuItem label actions ->
      [ indent indentLevel ++ "<item label=\"" ++ escapeXml label ++ "\">"
      ]
      ++ map (renderAction (indentLevel + 2)) actions
      ++ [indent indentLevel ++ "</item>"]
    MenuSeparator maybeLabel ->
      case maybeLabel of
        Nothing -> [indent indentLevel ++ "<separator />"]
        Just label -> [indent indentLevel ++ "<separator label=\"" ++ escapeXml label ++ "\" />"]
    MenuSubmenu submenu ->
      renderMenu indentLevel submenu

renderAction :: Int -> MenuAction -> String
renderAction indentLevel action =
  case action of
    Execute command ->
      indent indentLevel ++ "<action name=\"Execute\"><command>" ++ escapeXml command ++ "</command></action>"
    GoToDesktop index ->
      indent indentLevel ++ "<action name=\"GoToDesktop\" to=\"" ++ show index ++ "\" />"
    Reconfigure ->
      indent indentLevel ++ "<action name=\"Reconfigure\" />"
    Exit ->
      indent indentLevel ++ "<action name=\"Exit\" />"
    ShowMenu menuIdValue ->
      indent indentLevel ++ "<action name=\"ShowMenu\" menu=\"" ++ escapeXml menuIdValue ++ "\" />"

indent :: Int -> String
indent count = replicate count ' '
