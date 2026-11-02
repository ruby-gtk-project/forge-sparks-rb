{
  description = "forge-sparks — a Ruby GTK4 port";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Shared libraries every ruby-gnome extension links against.
        gtkStack = with pkgs; [
          glib
          gobject-introspection
          cairo
          pango
          gdk-pixbuf
          graphene
          atk
          gtk4
          libadwaita
          harfbuzz
          librsvg
        ]
        # The Ruby `pkg-config` gem resolves `Requires.private` transitively and
        # hard-fails if any .pc in the chain is missing, so gtk4's whole private
        # closure has to be on PKG_CONFIG_PATH, not just its public deps.
        ++ (with pkgs; [
          fontconfig
          freetype
          libepoxy
          libpng
          libxkbcommon
          pcre2
          util-linux
          wayland
          zlib
          fribidi
          libdatrie
          libthai
          libselinux
          libsepol
          expat
          brotli
          bzip2
          graphite2
          icu
          libffi
          libxml2
          lerc
          libdeflate
          xz
          zstd
        ])
        # Un-prefixed names: the `xorg.*` package set is deprecated.
        ++ (with pkgs; [
          libx11
          libxau
          libxcursor
          libxdmcp
          libxext
          libxfixes
          libxi
          libxinerama
          libxrandr
          libxrender
          libxcb
          xorgproto
        ]);

        # ruby-gnome gems build C extensions with extconf.rb + the pkg-config
        # gem; nixpkgs only ships gemConfig entries for the GTK3-era subset, so
        # the GTK4 gems get their build inputs declared here.
        rubyGnomeGem = _attrs: {
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = gtkStack;
        };

        gemConfig = pkgs.defaultGemConfig // {
          gdk4 = rubyGnomeGem;
          gsk4 = rubyGnomeGem;
          gtk4 = rubyGnomeGem;
          graphene1 = rubyGnomeGem;
          adwaita = rubyGnomeGem;
          rsvg2 = rubyGnomeGem;
        };

        # `makeSearchPath` would take each package's *first* output, and glib's
        # first output is `bin`, which carries no typelibs — hence the explicit
        # `.out`. at-spi2-core is here for the Atk typelib.
        typelibPath = pkgs.lib.makeSearchPath "lib/girepository-1.0"
          (map (drv: drv.out or drv) (gtkStack ++ [ pkgs.at-spi2-core ]));

        # nix/ and not the repo root: the root Gemfile is kettle-jem's
        # development bundle — rubocop, rspec, yard, the kettle-dev stack — and
        # must not end up in a packaged app's runtime closure. nix/Gemfile holds
        # the gemspec's runtime dependencies only.
        gems = pkgs.bundlerEnv {
          name = "forge-sparks-gems";
          ruby = pkgs.ruby_3_4;
          inherit gemConfig;
          gemdir = ./nix;
        };

        # The launcher is whatever the gemspec installs into exe/. Reading the
        # directory keeps this flake generic: no name to keep in step by hand.
        launcher = builtins.head (builtins.attrNames (builtins.readDir ./exe));

        # Optional directories: a port that has not grown translations or data
        # assets yet simply has none.
        optionalDirs = builtins.filter (d: builtins.pathExists (./. + "/${d}")) [
          "data"
          "po"
        ];

        # The app id is read off the packaging data in data/, the same way the
        # launcher is read off exe/: the desktop entry, the AppStream metainfo,
        # the D-Bus service and both icons all have to be installed under it,
        # and a name kept in step by hand is a name that drifts.
        dataNames =
          if builtins.pathExists ./data
          then builtins.attrNames (builtins.readDir ./data)
          else [ ];
        desktopTemplates = builtins.filter
          (n: builtins.match ".*\\.desktop\\.in" n != null)
          dataNames;
        appId =
          if desktopTemplates == [ ]
          then null
          else builtins.head (builtins.match "(.*)\\.desktop\\.in" (builtins.head desktopTemplates));

        # The text domain the app binds, which is the basename of every
        # compiled catalogue.
        textDomain = "forge-sparks";
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "forge-sparks";
          version = "0.1.0";
          src = ./.;

          # Deliberately no wrapGAppsHook4: glib's setup hook relocates
          # share/glib-2.0/schemas during fixup, after wrapGAppsHook4 has
          # computed its wrapper arguments, so a schema would end up somewhere
          # the wrapper never looks. The wrapper below is built by hand and
          # points at both the pre- and post-move paths.
          # gettext compiles the catalogues and merges them into the desktop
          # entry and the metainfo, which is what meson's i18n.merge_file does
          # for upstream.
          nativeBuildInputs = [ pkgs.makeWrapper pkgs.gettext pkgs.desktop-file-utils ];
          buildInputs = [ gems ] ++ gtkStack;

          dontBuild = true;

          installPhase = ''
            runHook preInstall

            mkdir -p $out/share/forge-sparks
            cp -r lib $out/share/forge-sparks/
            for d in ${pkgs.lib.escapeShellArgs optionalDirs}; do
              cp -r "$d" $out/share/forge-sparks/
            done
            # exe/ sits next to lib/ so the launcher's `require "forge-sparks"`
            # resolves against the copied tree.
            install -Dm755 exe/${launcher} $out/share/forge-sparks/exe/${launcher}

            # One compiled catalogue per po/<lang>.po, under the share the
            # wrapper puts on XDG_DATA_DIRS, which is where the app's
            # Translation looks for them.
            for po in po/*.po; do
              lang=$(basename "$po" .po)
              install -d $out/share/locale/$lang/LC_MESSAGES
              msgfmt "$po" -o $out/share/locale/$lang/LC_MESSAGES/${textDomain}.mo
            done
${pkgs.lib.optionalString (appId != null) ''
            # The desktop entry and the metainfo, each with the translations
            # of its own strings merged in from po/, the D-Bus service aimed
            # at the launcher this derivation installs, and the two icons under
            # the names the app asks the icon theme for.
            install -d $out/share/applications $out/share/metainfo $out/share/dbus-1/services
            msgfmt --desktop --template data/${appId}.desktop.in -d po \
              -o $out/share/applications/${appId}.desktop
            desktop-file-validate $out/share/applications/${appId}.desktop
            msgfmt --xml --template data/${appId}.metainfo.xml.in -d po \
              -o $out/share/metainfo/${appId}.metainfo.xml
            substitute data/${appId}.service.in \
              $out/share/dbus-1/services/${appId}.service \
              --replace-fail '@bindir@' "$out/bin"
            install -Dm644 data/forge-sparks.svg \
              $out/share/icons/hicolor/scalable/apps/${appId}.svg
            install -Dm644 data/forge-sparks-symbolic.svg \
              $out/share/icons/hicolor/symbolic/apps/${appId}-symbolic.svg
''}
            # Compile any GSettings schema the port ships.
            if [ -d data/schemas ]; then
              mkdir -p $out/share/glib-2.0/schemas
              cp data/schemas/*.gschema.xml $out/share/glib-2.0/schemas/
              ${pkgs.glib.dev}/bin/glib-compile-schemas $out/share/glib-2.0/schemas
            fi

            # -rbundler/setup puts the bundled gems on the load path, and
            # GI_TYPELIB_PATH keeps GObject-Introspection from re-registering
            # types the cairo gem's C extension has already registered.
            makeWrapper ${gems.wrappedRuby}/bin/ruby $out/bin/${launcher} \
              --add-flags "-rbundler/setup" \
              --add-flags "-I$out/share/forge-sparks/lib" \
              --add-flags "$out/share/forge-sparks/exe/${launcher}" \
              --set GI_TYPELIB_PATH "${typelibPath}" \
              --prefix XDG_DATA_DIRS : "$out/share" \
              --prefix XDG_DATA_DIRS : "$out/share/gsettings-schemas/forge-sparks-0.1.0" \
              --prefix XDG_DATA_DIRS : "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}" \
              --prefix XDG_DATA_DIRS : "${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}" \
              --prefix XDG_DATA_DIRS : "${pkgs.adwaita-icon-theme}/share"

            runHook postInstall
          '';

          meta = {
            description = "A Ruby GTK4 / Libadwaita port of forge-sparks";
            mainProgram = launcher;
            platforms = pkgs.lib.platforms.linux;
          };
        };

        apps.default = utils.lib.mkApp { drv = self.packages.${system}.default; };

        devShells.default = pkgs.mkShell {
          name = "forge-sparks-devshell";

          packages = [
            gems
            gems.wrappedRuby
            pkgs.bundler
            pkgs.bundix
            pkgs.pkg-config
            pkgs.glib.dev
            pkgs.gettext
            # rxgettext, the extractor `rake pot` drives. GNU xgettext claims
            # to support Ruby but only shells out to this, so without it
            # `xgettext --language=Ruby` fails.
            pkgs.rubyPackages_3_4.gettext
            # The spec runner. The suite is plain RSpec, so this is enough.
            pkgs.rubyPackages_3_4.rspec
            # This machine may have no display server at all, so the shell
            # carries one it can start itself: `xvfb-run ruby exe/<app>` both
            # launches the app and is how test/drive_*.rb is run.
            pkgs.xvfb-run
            pkgs.gsettings-desktop-schemas
            pkgs.adwaita-icon-theme
          ] ++ gtkStack;

          # Icons, GSettings schemas and the GTK portal all resolve through
          # XDG_DATA_DIRS; without these the window opens with blank icons.
          shellHook = ''
            export XDG_DATA_DIRS="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}:${pkgs.adwaita-icon-theme}/share:$XDG_DATA_DIRS"
            export GI_TYPELIB_PATH="${typelibPath}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
            export RUBYLIB="$PWD/lib''${RUBYLIB:+:$RUBYLIB}"
            [ -d data/schemas ] && export GSETTINGS_SCHEMA_DIR="$PWD/data/schemas"
            unset BUNDLE_GEMFILE BUNDLE_FROZEN
            echo "forge-sparks devshell — ruby $(ruby -e 'print RUBY_VERSION')"
            echo "run the app:   xvfb-run ruby exe/forge-sparks"
            echo "drive the app: xvfb-run ruby test/drive_*.rb"
            echo "run the specs: ruby -e 'require \"rspec/core\"; exit RSpec::Core::Runner.run([\"--format\", \"progress\", \"--require\", \"spec_helper\", \"spec\"])'"
          '';
        };
      });
}
