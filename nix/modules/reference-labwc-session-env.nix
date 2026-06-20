let
  settings = {
    NSCDE_LABWC_THEME_NAME = "NsCDE-Stage1";
    NSCDE_LABWC_WORKSPACES = "One,Two,Three,Four";
    NSCDE_LABWC_CURRENT_WORKSPACE = "One";
    NSCDE_LABWC_AUTOSTART_TERMINAL = 1;
  };
  renderLine = name: "${name}=${toString (builtins.getAttr name settings)}";
in
  builtins.concatStringsSep "\n" (map renderLine (builtins.attrNames settings)) + "\n"
