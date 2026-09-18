# nix/modules/pi/nixos-user.nix — NixOS module for delivering Pi
# config + managed packages to system service users (e.g. hermes agent
# profiles) via a system activation script.
#
# Unlike the Home Manager module (default.nix), this module targets system
# users who don't have a Home Manager configuration. It delivers the same
# makePiConfig static tree and the same makePiManagedPackages facades
# (identical store bits as the human-facing Home Manager module) through an
# activation script that links entries into a writable agent directory.
#
# The consumer's wrapper script sets PI_CODING_AGENT_DIR to
# <targetDir>/agent (see hermes' mkPiWrapper in the dotfiles repo). pi
# persists runtime selections (settings.json) and writes auth.json /
# models-store.json / sessions into that directory, so it must stay a real,
# user-owned tree — only individual entries are store symlinks.
#
# Usage in a NixOS config:
#   engineering-agents.pi-for-user = {
#     enable = true;
#     user = "hermes-dean";
#     group = "hermes-dean";
#     targetDir = "/var/lib/hermes/instances/dean/pi";
#     args = {
#       defaultProvider = "zai-coding-plan";
#       defaultModel = "glm-5.2";
#     };
#   };
#
{ self, llmAgents, visualExplainer }:

{ config, lib, pkgs, ... }:

let
  cfg = config.engineering-agents.pi-for-user;

  inherit (import ./config.nix { inherit lib pkgs self; })
    makePiConfig
    makePiManagedPackages
    defaultPowerlineTheme;

  forwardedArgs = cfg.args // {
    extraSkills = (cfg.args.extraSkills or { }) // lib.optionalAttrs cfg.enableVisualExplainer {
      visual-explainer = "${visualExplainer}/plugins/visual-explainer";
    };
  };

  # Static agent tree (settings.json inside is the declarative body; the
  # activation merges it into the target's writable settings.json).
  cfgStatic = makePiConfig forwardedArgs;

  # Same managed-packages derivation the Home Manager module consumes.
  cfgManaged = makePiManagedPackages {
    includeGitNexus = cfg.args.includeGitNexus or false;
    powerlineTheme = cfg.args.powerlineTheme or defaultPowerlineTheme;
  };
in
{
  options.engineering-agents.pi-for-user = {
    enable = lib.mkEnableOption "Pi agent config and managed packages for a system user";

    user = lib.mkOption {
      type = lib.types.str;
      description = "System user that will own the pi agent files.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      description = "System group that will own the pi agent files.";
    };

    targetDir = lib.mkOption {
      type = lib.types.str;
      description = ''
        Directory whose `agent/` subdir the consumer's wrapper passes as
        PI_CODING_AGENT_DIR. The activation script creates `agent/` under
        this directory and populates it with declarative config symlinks.
        The directory remains writable for pi's runtime state
        (settings.json, auth.json, models-store.json, sessions).
      '';
    };

    args = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Arguments forwarded to makePiConfig. See nix/modules/pi/config.nix
        for the full parameter signature. Common keys: defaultProvider,
        defaultModel, defaultThinkingLevel, theme, footer,
        enabledModels, includeGitNexus, powerline,
        powerlineShortcuts, powerlineTheme, extraSkills.
      '';
    };

    enableVisualExplainer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the visual-explainer skill.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = llmAgents.packages.${pkgs.system}.pi;
      description = ''
        Pi package this config targets. Consumers (e.g. a service wrapper)
        should exec this package's bin so the binary and the generated
        config always come from the same source.

        Not installed into any PATH by this module: the consumer's wrapper
        execs the absolute store path, and a systemd service PATH is
        explicit (it does not inherit user/system profiles).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Delivered via system.activationScripts (same reasoning as
    # opencode-for-user: tmpfiles refuses to write through non-root-owned
    # parent dirs, activation scripts don't). `ln -sfn` after `rm -rf`
    # force-updates across rebuilds, including over pre-existing real dirs.
    system.activationScripts."pi-for-user" = {
      deps = [ "users" "groups" ];
      text = ''
        set -euo pipefail
        agent="${cfg.targetDir}/agent"
        static=${cfgStatic}/agent
        managed=${cfgManaged}/agent

        mkdir -p "$agent/packages" "$agent/sources" "$agent/extensions"

        # Static tree: link every top-level entry except the two that must
        # stay real, user-owned files.
        for path in "$static"/*; do
          name="$(basename "$path")"
          case "$name" in
            settings.json|guardrails.json) continue ;;
            extensions)
              for sub in "$static"/extensions/*; do
                sub_name="$(basename "$sub")"
                rm -rf "$agent/extensions/$sub_name"
                ln -sfn "$sub" "$agent/extensions/$sub_name"
                chown -h ${cfg.user}:${cfg.group} "$agent/extensions/$sub_name"
              done
              ;;
            *)
              rm -rf "$agent/$name"
              ln -sfn "$path" "$agent/$name"
              chown -h ${cfg.user}:${cfg.group} "$agent/$name"
              ;;
          esac
        done

        # Managed packages: facades, sources, and the install-state
        # manifests consumed by the staleness checker.
        for path in "$managed"/packages/*; do
          name="$(basename "$path")"
          rm -rf "$agent/packages/$name"
          ln -sfn "$path" "$agent/packages/$name"
          chown -h ${cfg.user}:${cfg.group} "$agent/packages/$name"
        done
        for path in "$managed"/sources/*; do
          name="$(basename "$path")"
          rm -rf "$agent/sources/$name"
          ln -sfn "$path" "$agent/sources/$name"
          chown -h ${cfg.user}:${cfg.group} "$agent/sources/$name"
        done
        for entry in "$agent"/packages/*; do
          name="$(basename "$entry")"
          [ -e "$managed/packages/$name" ] || rm -rf "$entry"
        done
        for entry in "$agent"/sources/*; do
          name="$(basename "$entry")"
          [ -e "$managed/sources/$name" ] || rm -rf "$entry"
        done
        for f in managed-packages.declarations.json managed-packages.report.json managed-packages.install-state.json; do
          rm -f "$agent/$f"
          ln -sfn "$managed/$f" "$agent/$f"
          chown -h ${cfg.user}:${cfg.group} "$agent/$f"
        done

        # settings.json: real, user-owned, runtime-writable. Declarative
        # settings merge over the existing file (Nix wins on conflicts) so
        # pi's persisted runtime selections survive rebuilds.
        if [ -f "$agent/settings.json" ]; then
          ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$agent/settings.json" "$static/settings.json" > "$agent/settings.json.tmp" \
            && mv "$agent/settings.json.tmp" "$agent/settings.json"
        else
          cp "$static/settings.json" "$agent/settings.json"
        fi
        chown ${cfg.user}:${cfg.group} "$agent/settings.json"
        chmod 0644 "$agent/settings.json"

        # guardrails.json: real, user-owned copy installed only when absent;
        # the extension persists confirmed decisions into it and those must
        # survive rebuilds.
        if [ ! -f "$agent/guardrails.json" ]; then
          cp "$static/guardrails.json" "$agent/guardrails.json"
          chown ${cfg.user}:${cfg.group} "$agent/guardrails.json"
        fi
        chmod 0644 "$agent/guardrails.json" 2>/dev/null || true

        # The agent dir itself stays group-traversable but not world-open,
        # mirroring the hermes instance-root convention.
        chown ${cfg.user}:${cfg.group} "$agent"
        chmod 0750 "$agent"
      '';
    };
  };
}
