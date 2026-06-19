# nix/modules/opencode/nixos-user.nix — NixOS module for delivering OpenCode
# config to system service users (e.g., hermes) via systemd.tmpfiles.
#
# Unlike the Home Manager module (default.nix), this module targets system
# users who don't have a Home Manager configuration. It delivers the same
# makeOpenCodeConfig derivation via tmpfiles rules that symlink individual
# files into a writable target directory.
#
# Usage in a NixOS config:
#   engineering-agents.opencode-for-user = {
#     enable = true;
#     user = "hermes";
#     group = "hermes";
#     targetDir = "/var/lib/hermes/.hermes/profiles/clarity-lens/opencode/config";
#     args = {
#       model = "zai-coding-plan/glm-5.2";
#       providers = "zai-only";
#       plugins = "minimal";
#     };
#   };
#
{ self }:

{ config, lib, pkgs, ... }:

let
  cfg = config.engineering-agents.opencode-for-user;
  inherit (import ./config.nix { inherit lib pkgs self; }) makeOpenCodeConfig;
in
{
  options.engineering-agents.opencode-for-user = {
    enable = lib.mkEnableOption "OpenCode config for a system user";

    user = lib.mkOption {
      type = lib.types.str;
      description = "System user that will own the opencode config files.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      description = "System group that will own the opencode config files.";
    };

    targetDir = lib.mkOption {
      type = lib.types.str;
      description = ''
        Directory whose `opencode/` subdir opencode reads as XDG_CONFIG_HOME.
        The consumer's wrapper script should set XDG_CONFIG_HOME to this path.
        tmpfiles will create `opencode/` under this directory and populate it
        with declarative config symlinks. The directory remains writable for
        opencode's runtime plugin npm-install (package.json, bun.lock,
        node_modules).
      '';
    };

    args = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = ''
        Arguments forwarded to makeOpenCodeConfig. See
        nix/modules/opencode/config.nix for the full parameter signature.
        Common keys: model, plugins ("default"|"minimal"|list), providers
        ("default"|"zai-only"|attrs), mcp, enableTmux, agentModelOverrides,
        categoryOverrides.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = let cfgd = makeOpenCodeConfig cfg.args; in [
      "d  ${cfg.targetDir}/opencode                     0750 ${cfg.user} ${cfg.group} -"
      "L+ ${cfg.targetDir}/opencode/opencode.json        - ${cfg.user} ${cfg.group} - ${cfgd}/opencode/opencode.json"
      "L+ ${cfg.targetDir}/opencode/tui.json             - ${cfg.user} ${cfg.group} - ${cfgd}/opencode/tui.json"
      "L+ ${cfg.targetDir}/opencode/oh-my-openagent.json - ${cfg.user} ${cfg.group} - ${cfgd}/opencode/oh-my-openagent.json"
      "L  ${cfg.targetDir}/opencode/agents               - ${cfg.user} ${cfg.group} - ${cfgd}/opencode/agents"
      "L  ${cfg.targetDir}/opencode/skills               - ${cfg.user} ${cfg.group} - ${cfgd}/opencode/skills"
    ];
  };
}
