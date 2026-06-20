{
  description = "Standalone bootstrap for the NsCDE Wayland rewrite";

  inputs = {
    self.submodules = true;
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        labwcSrc = builtins.path {
          path = ./labwc;
          name = "nscde-wayland-labwc-source";
        };
        python = pkgs.python3.withPackages (ps: with ps; [
          psutil
          pyxdg
          pyyaml
          pyqt5
        ]);
        labwcPkg = pkgs.stdenv.mkDerivation {
          pname = "labwc";
          version = "0.20.0";
          src = labwcSrc;

          nativeBuildInputs = with pkgs; [
            gettext
            meson
            ninja
            pkg-config
            scdoc
            wayland-scanner
            versionCheckHook
          ];

          buildInputs = with pkgs; [
            cairo
            glib
            libdrm
            libinput
            libpng
            librsvg
            libsfdo
            libxcb
            libxkbcommon
            libxml2
            pango
            wayland
            wayland-protocols
            wlroots
            xcbutilwm
            xwayland
          ];

          mesonFlags = [
            (pkgs.lib.mesonEnable "xwayland" true)
            "-Dsystemd-session=disabled"
            "-Dman-pages=disabled"
            "-Dtest=disabled"
          ];

          strictDeps = true;
          doInstallCheck = true;
          versionCheckProgramArg = "--version";
          meta.mainProgram = "labwc";
        };
        referencePanelLayoutFile =
          pkgs.writeText "reference-panel-layout.env" (import ./nix/modules/reference-panel-layout.nix);
        referenceSessionEnvFile =
          pkgs.writeText "reference-labwc-session-env.env" (import ./nix/modules/reference-labwc-session-env.nix);
        workspaceSrc = ./.;
        runtimePkg = pkgs.haskellPackages.callCabal2nix "nscde-wayland-runtime" workspaceSrc { };
        buildNativeClient =
          { pname
          , version ? "0.1.0"
          , sources
          , buildInputs ? [ ]
          , extraFlags ? [ ]
          , extraInstall ? ""
          }:
          pkgs.stdenv.mkDerivation {
            inherit pname version;
            src = workspaceSrc;
            dontConfigure = true;
            nativeBuildInputs = [ pkgs.pkg-config ];
            buildInputs = [ pkgs.wayland ] ++ buildInputs;
            buildPhase =
              let
                sourceArgs = builtins.concatStringsSep " " sources;
                flagArgs = builtins.concatStringsSep " " extraFlags;
              in ''
                runHook preBuild
                cc -O2 -std=c11 -o ${pname} ${sourceArgs} ${flagArgs}
                runHook postBuild
              '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/bin"
              install -m755 ${pname} "$out/bin/${pname}"
              ${extraInstall}
              runHook postInstall
            '';
          };
        paneldPkg = buildNativeClient {
          pname = "nscde_paneld";
          sources = [
            "src/nscde_paneld/nscde_paneld.c"
            "src/nscde_paneld/nscde-pixel-icon.c"
            "src/nscde_paneld/pool-buffer.c"
            "src/nscde_paneld/wlr-layer-shell-unstable-v1-protocol.c"
            "src/nscde_paneld/xdg-shell-protocol.c"
            "src/nscde_wayland_common/panel-layout-contract.c"
            "src/nscde_wayland_common/runtime-client.c"
          ];
          buildInputs = [
            pkgs.cairo
            pkgs.pango
          ];
          extraFlags = [
            "-D_GNU_SOURCE"
            "$(pkg-config --cflags --libs wayland-client cairo pangocairo)"
            "-lm"
          ];
        };
        pagerdPkg = buildNativeClient {
          pname = "nscde_pagerd";
          sources = [
            "src/nscde_pagerd/nscde_pagerd.c"
            "src/nscde_pagerd/ext-workspace-v1-protocol.c"
          ];
          extraFlags = [
            "$(pkg-config --cflags --libs wayland-client)"
          ];
        };
        toplevelPkg = buildNativeClient {
          pname = "nscde_toplevel";
          sources = [
            "src/nscde_toplevel/nscde_toplevel.c"
            "src/nscde_toplevel/wlr-foreign-toplevel-management-unstable-v1-protocol.c"
          ];
          extraFlags = [
            "$(pkg-config --cflags --libs wayland-client)"
          ];
        };
        nativeClientsPkg = pkgs.symlinkJoin {
          name = "nscde-wayland-clients";
          paths = [
            paneldPkg
            pagerdPkg
            toplevelPkg
          ];
        };
        launcherRuntimePath = pkgs.lib.makeBinPath [
          pkgs.coreutils
          pkgs.dbus
          pkgs.findutils
          pkgs.fontconfig
          pkgs.gawk
          pkgs.gnugrep
          pkgs.gnused
          pkgs.imagemagick
          pkgs.inotify-tools
          pkgs.ksh
          labwcPkg
          pkgs.procps
          pkgs.swaybg
          pkgs.weston
          pkgs.wlr-randr
          pkgs.xterm
        ];
        launcherPkg = pkgs.stdenv.mkDerivation {
          pname = "nscde-wayland-bootstrap";
          version = "0.1.0";
          src = workspaceSrc;
          dontConfigure = true;
          dontBuild = true;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          installPhase = ''
            datadir="$out/share/nscde"
            libdir="$out/lib/nscde"
            tooldir="$out/libexec/nscde/tools"
            archdir="$tooldir/$(uname -s)_$(uname -m)"

            mkdir -p \
              "$out/bin" \
              "$out/share/applications" \
              "$out/share/desktop-directories" \
              "$out/share/icons" \
              "$out/share/menus" \
              "$out/share/wayland-sessions" \
              "$datadir" \
              "$libdir/python" \
              "$tooldir" \
              "$archdir"

            cp -a assets/. "$datadir/"
            cp -a xdg/applications/. "$out/share/applications/"
            cp -a xdg/desktop-directories/. "$out/share/desktop-directories/"
            cp -a xdg/icons/NsCDE "$out/share/icons/"
            cp -a xdg/menus/. "$out/share/menus/"

            cat > "$out/share/wayland-sessions/nscde-labwc.desktop" <<EOF
[Desktop Entry]
Name=NsCDE (Wayland)
Comment=Not so Common Desktop Environment on labwc
Exec=$out/bin/nscde_labwc_session
TryExec=$out/bin/nscde_labwc_session
Type=Application
DesktopNames=NsCDE
EOF

            substitute_template() {
              src_file="$1"
              dest_file="$2"
              substitute "$src_file" "$dest_file" \
                --replace-quiet '@KSH@' '${pkgs.ksh}/bin/ksh' \
                --replace-quiet '@PYTHON@' '${python}/bin/python3' \
                --replace-quiet '@prefix@' "$out" \
                --replace-quiet '@VERSION@' 'standalone-bootstrap' \
                --replace-quiet '@NSCDE_DATADIR@' "$datadir" \
                --replace-quiet '@NSCDE_LIBDIR@' "$libdir" \
                --replace-quiet '@NSCDE_TOOLSDIR@' "$tooldir" \
                --replace-quiet '@FVWM_DATADIR@' "$datadir/fvwm" \
                --replace-quiet '@ECHONE@' 'printf %s' \
                --replace-quiet '@CONVERT@' '${pkgs.imagemagick}/bin/magick' \
                --replace-quiet '@DEFAULT_SINK@' '@DEFAULT_SINK@' \
                --replace-quiet '@NOSTDICONDIR@' '/usr/share/icons' \
                --replace-quiet '@NOSTDICONDIRREGEX@' '^\/usr\/share\/icons\/\|^\/usr\/local\/share\/icons\/' \
                --replace-quiet '@NOSTDICONPATH@' '/usr/share/icons:/usr/local/share/icons'
            }

            for src_file in lib/python/*.py.in; do
              base="$(basename "$src_file" .in)"
              substitute_template "$src_file" "$libdir/python/$base"
              chmod 644 "$libdir/python/$base"
            done

            for src_file in legacy-shims/*.in; do
              base="$(basename "$src_file" .in)"
              if [ "$base" = "nscde_labwc_menugen" ]; then
                continue
              fi
              substitute_template "$src_file" "$tooldir/$base"
              chmod +x "$tooldir/$base"
            done

            substitute_template bin/nscde_labwc.in "$out/bin/nscde_labwc"
            chmod +x "$out/bin/nscde_labwc"

            cat > "$out/bin/nscde_labwc_session" <<EOF
#!/bin/sh
if [ -n "''${WAYLAND_DISPLAY:-}" ] || [ -n "''${DISPLAY:-}" ]; then
   if [ "''${NSCDE_ALLOW_NESTED_SESSION:-0}" != "1" ]; then
      echo "nscde_labwc_session: existing graphical session detected." >&2
      echo "Use this launcher from a display manager Wayland session or VT login." >&2
      echo "For nested testing, use nscde_labwc directly or set NSCDE_ALLOW_NESTED_SESSION=1." >&2
      exit 2
   fi
fi

if [ -z "''${XDG_RUNTIME_DIR:-}" ]; then
   echo "nscde_labwc_session: XDG_RUNTIME_DIR is not set." >&2
   echo "Log in through a Wayland-capable display manager or PAM/systemd user session." >&2
   exit 2
fi

export NSCDE_BACKEND=labwc
export XDG_CURRENT_DESKTOP=NsCDE
export XDG_SESSION_DESKTOP=NsCDE
export DESKTOP_SESSION=NsCDE
export XDG_SESSION_TYPE=wayland

if [ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
   exec dbus-run-session "$out/bin/nscde_labwc" "$@"
fi

exec "$out/bin/nscde_labwc" "$@"
EOF
            chmod +x "$out/bin/nscde_labwc_session"

            ln -s ${runtimePkg}/bin/nscde-runtime "$out/bin/nscde-runtime"
            ln -s ${paneldPkg}/bin/nscde_paneld "$archdir/nscde_paneld"
            ln -s ${pagerdPkg}/bin/nscde_pagerd "$archdir/nscde_pagerd"
            ln -s ${toplevelPkg}/bin/nscde_toplevel "$archdir/nscde_toplevel"

            wrapProgram "$out/bin/nscde_labwc" \
              --prefix PATH : ${launcherRuntimePath} \
              --set-default NSCDE_RUNTIME_BIN "$out/bin/nscde-runtime" \
              --set-default NSCDE_STATIC_PANEL_LAYOUT_FILE "${referencePanelLayoutFile}" \
              --set-default NSCDE_STATIC_SESSION_ENV_FILE "${referenceSessionEnvFile}" \
              --set-default LABWC_BIN "${labwcPkg}/bin/labwc"

            wrapProgram "$out/bin/nscde_labwc_session" \
              --prefix PATH : ${launcherRuntimePath}
          '';
        };
        runtimeCheckApp = pkgs.writeShellApplication {
          name = "nscde-wayland-runtime-check";
          runtimeInputs = [
            runtimePkg
            launcherPkg
            pkgs.coreutils
            pkgs.gnugrep
          ];
          text = ''
            export NSCDE_RUNTIME_BIN="${runtimePkg}/bin/nscde-runtime"
            export NSCDE_RUNTIME_ROOT="${./.}"
            export NSCDE_RUNTIME_TOOLSDIR="${launcherPkg}/libexec/nscde/tools"
            export NSCDE_STATIC_PANEL_LAYOUT_FILE="${referencePanelLayoutFile}"
            export NSCDE_STATIC_SESSION_ENV_FILE="${referenceSessionEnvFile}"
            exec ${./tools/check-runtime.sh}
          '';
        };
        launcherCheckApp = pkgs.writeShellApplication {
          name = "nscde-wayland-launcher-check";
          runtimeInputs = [
            launcherPkg
            pkgs.coreutils
            pkgs.gnugrep
          ];
          text = ''
            export NSCDE_LAUNCHER_BIN="${launcherPkg}/bin/nscde_labwc"
            exec ${./tools/check-launcher.sh}
          '';
        };
      in {
        packages = {
          default = launcherPkg;
          labwc = labwcPkg;
          nscde-wayland-bootstrap = launcherPkg;
          nscde-runtime = runtimePkg;
          nscde-wayland-clients = nativeClientsPkg;
          nscde-labwc = launcherPkg;
          nscde-paneld = paneldPkg;
          nscde-pagerd = pagerdPkg;
          nscde-toplevel = toplevelPkg;
          reference-panel-layout = referencePanelLayoutFile;
          reference-labwc-session-env = referenceSessionEnvFile;
          launcher-check = launcherCheckApp;
          runtime-check = runtimeCheckApp;
        };

        apps = {
          default = {
            type = "app";
            program = "${launcherPkg}/bin/nscde_labwc";
          };
          nscde-labwc = {
            type = "app";
            program = "${launcherPkg}/bin/nscde_labwc";
          };
          nscde-labwc-session = {
            type = "app";
            program = "${launcherPkg}/bin/nscde_labwc_session";
          };
          nscde-runtime = {
            type = "app";
            program = "${runtimePkg}/bin/nscde-runtime";
          };
          launcher-check = {
            type = "app";
            program = "${launcherCheckApp}/bin/nscde-wayland-launcher-check";
          };
          runtime-check = {
            type = "app";
            program = "${runtimeCheckApp}/bin/nscde-wayland-runtime-check";
          };
        };

        checks = {
          nscde-wayland-bootstrap = launcherPkg;
          nscde-runtime = runtimePkg;
          nscde-wayland-clients = nativeClientsPkg;
          nscde-labwc = launcherPkg;
          nscde-paneld = paneldPkg;
          nscde-pagerd = pagerdPkg;
          nscde-toplevel = toplevelPkg;
          launcher-check = pkgs.runCommand "nscde-wayland-launcher-check" {
            nativeBuildInputs = [
              launcherPkg
              pkgs.coreutils
              pkgs.gnugrep
            ];
            NSCDE_LAUNCHER_BIN = "${launcherPkg}/bin/nscde_labwc";
          } ''
            ${./tools/check-launcher.sh}
            touch "$out"
          '';
          runtime-check = pkgs.runCommand "nscde-wayland-runtime-check" {
            nativeBuildInputs = [
              runtimePkg
              launcherPkg
              pkgs.coreutils
              pkgs.gnugrep
            ];
            NSCDE_RUNTIME_BIN = "${runtimePkg}/bin/nscde-runtime";
            NSCDE_RUNTIME_ROOT = ./.;
            NSCDE_RUNTIME_TOOLSDIR = "${launcherPkg}/libexec/nscde/tools";
            NSCDE_STATIC_PANEL_LAYOUT_FILE = referencePanelLayoutFile;
            NSCDE_STATIC_SESSION_ENV_FILE = referenceSessionEnvFile;
          } ''
            ${./tools/check-runtime.sh}
            touch "$out"
          '';
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [
            labwcPkg
            runtimePkg
            nativeClientsPkg
            launcherPkg
          ];
          packages = with pkgs; [
            autoconf
            automake
            cabal-install
            cairo
            expat
            fontconfig
            fribidi
            gcc
            gettext
            glib
            gnumake
            ghc
            haskell-language-server
            inotify-tools
            ksh
            libdrm
            libpng
            libsfdo
            libxkbcommon
            libxml2
            pango
            pkg-config
            python
            wayland
            wayland-protocols
            wayland-scanner
            wlroots
          ];

          shellHook = ''
            export NSCDE_WAYLAND_ROOT="$PWD"
            export NSCDE_WAYLAND_ASSETS_DIR="$PWD/assets"
            export NSCDE_WAYLAND_XDG_DIR="$PWD/xdg"
            export NSCDE_STATIC_PANEL_LAYOUT_FILE="${referencePanelLayoutFile}"
            export NSCDE_STATIC_SESSION_ENV_FILE="${referenceSessionEnvFile}"
            echo "NsCDE-Wayland shell ready: nix run .#launcher-check, nix run .#runtime-check, nix build ., or cabal build"
          '';
        };
      });
}
