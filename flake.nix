{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    astal = {
      url = "github:aylur/astal";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    astal,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    wrappedPackage = pkgs: let
      giPackages = with pkgs; [
        glib
        gtk3
        gobject-introspection
        gsettings-desktop-schemas
        gdk-pixbuf
        pango
        cairo
        atk
      ];

      astalPackages = with astal.packages.${system}; [
        battery
        astal3
        io
        apps
        bluetooth
        mpris
        network
        notifd
        powerprofiles
        tray
        wireplumber
      ];

      utilPackages = with pkgs; [
        dart-sass
        inotify-tools
        brightnessctl
        gammastep
        wget
        curl
        fastfetch
      ];

      luaPackages = with pkgs.lua52Packages; [
        cjson
        luautf8
        lgi
      ];

      basePackage = astal.lib.mkLuaPackage {
        inherit pkgs;
        name = "kaneru";
        src = ./.;
        extraPackages = astalPackages ++ utilPackages ++ giPackages ++ luaPackages;
      };

      wrapper = pkgs.writeShellScript "kaneru-wrapper" ''
        export LUA_PATH="''${LUA_PATH:-};${pkgs.lib.concatMapStringsSep ";"
          (pkg: "${pkg}/share/lua/5.2/?.lua;${pkg}/share/lua/5.2/?/init.lua")
          luaPackages};"

        export LUA_CPATH="''${LUA_CPATH:-};${pkgs.lib.concatMapStringsSep ";"
          (pkg: "${pkg}/lib/lua/5.2/?.so")
          luaPackages};"

        export GI_TYPELIB_PATH="${pkgs.lib.makeSearchPath "lib/girepository-1.0"
          (astalPackages ++ giPackages)}"

        export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath
          (astalPackages ++ giPackages)}"

        export XDG_DATA_DIRS="${pkgs.lib.concatMapStringsSep ":"
          (pkg: "${pkg}/share")
          (giPackages ++ astalPackages)}:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

        echo "LUA_PATH: $LUA_PATH"
        echo "LUA_CPATH: $LUA_CPATH"
        echo "GI_TYPELIB_PATH: $GI_TYPELIB_PATH"
        echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
        echo "XDG_DATA_DIRS: $XDG_DATA_DIRS"

        exec ${basePackage}/bin/.kaneru-wrapped "$@"
      '';
    in
      pkgs.symlinkJoin {
        name = "kaneru";
        paths = [basePackage];
        buildInputs = [pkgs.makeWrapper];
        postBuild = ''
          rm $out/bin/kaneru
          cp ${wrapper} $out/bin/kaneru
          chmod +x $out/bin/kaneru
        '';
      };
  in {
    packages.${system} = {
      default = wrappedPackage pkgs;
    };

    nixosModules.default = import ./nix/nixos-module.nix {inherit self;};
    homeManagerModules.default = import ./nix/hm-module.nix {inherit self;};
  };
}
