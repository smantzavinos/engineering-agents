# OpenCode CLI Home Manager module
#
# Declarative configuration for OpenCode and its plugins.
# OpenCode auto-manages npm dependencies.
#
# This module is a thin shim that delegates config generation to
# makeOpenCodeConfig (see ./config.nix). The derivation produces the complete
# opencode/ directory tree; this module links individual files/subdirs into
# ~/.config/opencode/ via xdg.configFile.
#
# IMPORTANT: link individual files/subdirs, NOT the whole "opencode" dir.
# opencode writes package.json / bun.lock / node_modules into
# ~/.config/opencode/ at runtime (plugin npm install). A whole-directory
# source would symlink the entire dir read-only from the Nix store and
# break plugin installation.
#
# Usage in your home-manager config:
#   imports = [ engineering-agents.homeManagerModules.opencode ];
#   engineering-agents.opencode.enable = true;
#
{ self, llmAgents, visualExplainer }:

{ config, lib, pkgs, ... }:

let
  cfg = config.engineering-agents.opencode;
  inherit (import ./config.nix { inherit lib pkgs self; }) makeOpenCodeConfig;
in
{
  options.engineering-agents.opencode = {
    enable = lib.mkEnableOption "OpenCode CLI with engineering-agents configuration";

    model = lib.mkOption {
      type = lib.types.str;
      default = "zai-coding-plan/glm-5.2";
      description = "Default OpenCode model";
    };

    enableTmux = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable tmux integration for background subagents";
    };

    enableVisualExplainer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the visual-explainer skill";
    };

    enableServer = lib.mkEnableOption "OpenCode server systemd service";
    serverPort = lib.mkOption {
      type = lib.types.port;
      default = 3124;
      description = "Port for the OpenCode server";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      llmAgents.packages.${pkgs.system}.opencode
    ];

    # Delegate to makeOpenCodeConfig derivation — individual file/subdir links
    # leave the parent ~/.config/opencode/ real and writable for opencode's
    # runtime plugin npm-install (package.json, bun.lock, node_modules).
    xdg.configFile = let
      cfgd = makeOpenCodeConfig {
        inherit (cfg) model enableTmux;
        extraSkills = lib.optionalAttrs cfg.enableVisualExplainer {
          visual-explainer = "${visualExplainer}/plugins/visual-explainer";
        };
      };
    in {
      "opencode/opencode.json".source        = "${cfgd}/opencode/opencode.json";
      "opencode/tui.json".source             = "${cfgd}/opencode/tui.json";
      "opencode/oh-my-openagent.json".source = "${cfgd}/opencode/oh-my-openagent.json";
      "opencode/agents".source               = "${cfgd}/opencode/agents";
      "opencode/skills".source               = "${cfgd}/opencode/skills";
    };
  };
}
