{self}: {
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.services.astal-bar;

  toLua = value:
    if lib.isAttrs value
    then
      "{\n"
      + lib.concatStringsSep ",\n" (lib.mapAttrsToList (
          k: v: "\t${k} = ${toLua v}"
        )
        value)
      + "\n}"
    else if lib.isList value
    then
      "{\n\t"
      + lib.concatMapStringsSep ",\n\t" (
        v:
          if builtins.isString v
          then "\"${v}\""
          else toLua v
      )
      value
      + "\n}"
    else if builtins.isString value
    then ''"${value}"''
    else if builtins.isInt value || builtins.isFloat value
    then toString value
    else if value == true
    then "true"
    else if value == false
    then "false"
    else if value == null
    then "nil"
    else abort "Unsupported Lua value type";

  configFile = pkgs.writeText "user-variables.lua" "return ${toLua cfg.settings}";
in {
  options = {
    services.astal-bar = {
      enable = lib.mkEnableOption "Astal Bar";

      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${pkgs.system}.default;
        description = "The Astal Bar package to use";
      };

      settings = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        example = lib.literalExpression ''
          {
            dock.pinned_apps = [ "firefox" "kitty" ];
            github.username = "yourusername";
            monitor.mode = "primary";
          }
        '';
        description = "Astal Bar configuration options";
      };

      autostart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to start Astal Bar automatically";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    environment.etc."kaneru/user-variables.lua".source = configFile;

    systemd.user.services.astal-bar = lib.mkIf cfg.autostart {
      description = "Astal Bar";
      wantedBy = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      after = ["graphical-session-pre.target"];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/kaneru";
        Restart = "on-failure";
      };
    };
  };
}
