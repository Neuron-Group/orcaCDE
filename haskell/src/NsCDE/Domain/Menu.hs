module NsCDE.Domain.Menu
  ( AppMenuEntry(..)
  , Menu(..)
  , MenuAction(..)
  , MenuElement(..)
  ) where

data AppMenuEntry = AppMenuEntry
  { appMenuClass :: String
  , appMenuRawLabel :: String
  , appMenuDisplayLabel :: String
  , appMenuAction :: String
  , appMenuSortLine :: String
  } deriving (Eq, Show)

data Menu = Menu
  { menuId :: String
  , menuLabel :: String
  , menuElements :: [MenuElement]
  } deriving (Eq, Show)

data MenuElement
  = MenuItem String [MenuAction]
  | MenuSeparator (Maybe String)
  | MenuSubmenu Menu
  deriving (Eq, Show)

data MenuAction
  = Execute String
  | GoToDesktop Int
  | Reconfigure
  | Exit
  | ShowMenu String
  deriving (Eq, Show)
