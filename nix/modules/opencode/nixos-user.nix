# nix/modules/opencode/nixos-user.nix — NixOS module for delivering OpenCode
# config to system service users (e.g., hermes) via a system activation script.
#
# Unlike the Home Manager module (default.nix), this module targets system
# users who don't have a Home Manager configuration. It delivers the same
# makeOpenCodeConfig derivation via an activation script that symlinks
# individual files into a writable target directory.
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
{ self, llmAgents, visualExplainer }:

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
        The activation script creates `opencode/` under this directory and
        populates it with declarative config symlinks. The directory remains
        writable for opencode's runtime plugin npm-install (package.json,
        bun.lock, node_modules).
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

    enableVisualExplainer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the visual-explainer skill.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = llmAgents.packages.${pkgs.system}.opencode;
      description = ''
        OpenCode package this config targets. Consumers (e.g. a service
        wrapper) should exec this package's bin so the binary and the
        generated config always come from the same source.

        Not installed into any PATH by this module: the consumer's wrapper
        execs the absolute store path, and a systemd service PATH is explicit
        (it does not inherit user/system profiles). This intentionally
        diverges from the Home Manager module's home.packages install (see
        default.nix), because that mechanism does not apply to a system
        service user.
      '';
    };
  };

  config = lib.mkIf cfg.enable (let
    forwardedArgs = cfg.args // {
      extraSkills = (cfg.args.extraSkills or {}) // lib.optionalAttrs cfg.enableVisualExplainer {
        visual-explainer = "${visualExplainer}/plugins/visual-explainer";
      };
    };
    cfgd = makeOpenCodeConfig forwardedArgs;
  in {
    # Delivered via system.activationScripts, NOT systemd.tmpfiles.rules.
    # tmpfiles runs as root and refuses to write into any path that passes
    # through a non-root-owned directory ("unsafe path transition" —
    # anti-symlink-attack protection), so it silently no-ops for a targetDir
    # under a user-owned tree (e.g. /var/lib/hermes/.hermes, owned by hermes)
    # and the config is never materialized. Activation scripts run as root via
    # plain bash with no such canonicalization check, so they can place the
    # symlinks under a user-owned path. `ln -sfn` keeps them force-updated
    # across rebuilds (no L-vs-L+ fragility).
    system.activationScripts."opencode-for-user" = {
      deps = [ "users" "groups" ];
      text = ''
        target="${cfg.targetDir}/opencode"
        mkdir -p "$target"
        chown ${cfg.user}:${cfg.group} "$target"
        chmod 0750 "$target"
        ln -sfn ${cfgd}/opencode/opencode.json        "$target/opencode.json"
        ln -sfn ${cfgd}/opencode/tui.json             "$target/tui.json"
        ln -sfn ${cfgd}/opencode/oh-my-openagent.json "$target/oh-my-openagent.json"
        ln -sfn ${cfgd}/opencode/agents               "$target/agents"
        ln -sfn ${cfgd}/opencode/skills               "$target/skills"
        chown -h ${cfg.user}:${cfg.group} "$target/opencode.json" "$target/tui.json" "$target/oh-my-openagent.json" "$target/agents" "$target/skills"
      '';
    };
  });
}
