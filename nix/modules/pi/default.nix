# Pi coding agent Home Manager module
#
# Declarative configuration for the pi-mono coding agent.
# Installs Pi, managed packages, skills, agents, and presets.
#
# Usage in your home-manager config:
#   imports = [ engineering-agents.homeManagerModules.pi ];
#   engineering-agents.pi.enable = true;
#
# Then: home-manager switch --flake .#<hostname>
#
{ self, llmAgents, visualExplainer, agentKit }:

{ config, lib, pkgs, ... }:

let
  cfg = config.engineering-agents.pi;

  # Managed Pi package declarations
  piPackages = {
    pi-subagents = {
      source = {
        type = "git";
        packageName = "pi-subagents";
        spec = "github:nicobailon/pi-subagents#c940fe20e86d9ba429eebcac809ec79d478ef206";
        installSpec = "github:nicobailon/pi-subagents#c940fe20e86d9ba429eebcac809ec79d478ef206";
      };
    };

    pi-hooks = {
      source = {
        type = "git";
        packageName = "pi-hooks";
        spec = "github:smantzavinos/pi-hooks#1c3ed591b393793cd025ff43fa61e16828872931";
        installSpec = "github:smantzavinos/pi-hooks#1c3ed591b393793cd025ff43fa61e16828872931";
      };
    };

    pi-agent-guidance = {
      source = {
        type = "npm";
        packageName = "@tmustier/pi-agent-guidance";
        spec = "@tmustier/pi-agent-guidance@0.1.3";
        installSpec = "@tmustier/pi-agent-guidance@0.1.5";
        version = "0.1.5";
      };
    };

    pi-mcp-adapter = {
      source = {
        type = "npm";
        packageName = "pi-mcp-adapter";
        spec = "pi-mcp-adapter@2.11.0";
        installSpec = "pi-mcp-adapter@2.11.0";
        version = "2.11.0";
      };
    };

    pi-web-access = {
      source = {
        type = "npm";
        packageName = "pi-web-access";
        spec = "pi-web-access@0.10.6";
        installSpec = "pi-web-access@0.13.0";
        version = "0.13.0";
      };
    };

    pi-powerline-footer = {
      source = {
        type = "npm";
        packageName = "pi-powerline-footer";
        spec = "pi-powerline-footer@0.4.9";
        installSpec = "pi-powerline-footer@0.6.1";
        version = "0.6.1";
      };
    };

    pi-interactive-shell = {
      source = {
        type = "npm";
        packageName = "pi-interactive-shell";
        spec = "pi-interactive-shell@0.10.7";
        installSpec = "pi-interactive-shell@0.13.0";
        version = "0.13.0";
      };
    };

    pi-subdir-context = {
      source = {
        type = "npm";
        packageName = "pi-subdir-context";
        spec = "pi-subdir-context@1.1.2";
        installSpec = "pi-subdir-context@1.1.7";
        version = "1.1.7";
      };
    };

    pi-ding = {
      source = {
        type = "npm";
        packageName = "pi-ding";
        spec = "pi-ding@0.2.2";
        installSpec = "pi-ding@0.2.2";
        version = "0.2.2";
      };
    };

    pi-notify = {
      source = {
        type = "npm";
        packageName = "pi-notify";
        spec = "pi-notify@1.3.0";
        installSpec = "pi-notify@1.4.0";
        version = "1.4.0";
      };
    };

    pi-auto-rename = {
      source = {
        type = "npm";
        packageName = "@byteowlz/pi-auto-rename";
        spec = "@byteowlz/pi-auto-rename@1.0.7";
        installSpec = "@byteowlz/pi-auto-rename@1.0.7";
        version = "1.0.7";
      };
    };

    pi-ext-leader-key = {
      source = {
        type = "git";
        packageName = "pi-ext";
        spec = "github:tomsej/pi-ext#d162f4c47ae82d2cdb5d1d499136601ff8718303";
        installSpec = "github:tomsej/pi-ext#d162f4c47ae82d2cdb5d1d499136601ff8718303";
      };
      expose = {
        extensions = [ "./extensions/leader-key/index.ts" ];
        skills = [ ];
        prompts = [ ];
        themes = [ ];
      };
    };

    pi-ext-review = {
      source = {
        type = "git";
        packageName = "pi-ext";
        spec = "github:tomsej/pi-ext#d162f4c47ae82d2cdb5d1d499136601ff8718303";
        installSpec = "github:tomsej/pi-ext#d162f4c47ae82d2cdb5d1d499136601ff8718303";
      };
      expose = {
        extensions = [ "./extensions/review/review.ts" ];
        skills = [ ];
        prompts = [ ];
        themes = [ ];
      };
    };

    pi-guardrails = {
      source = {
        type = "npm";
        packageName = "@aliou/pi-guardrails";
        spec = "@aliou/pi-guardrails@0.9.5";
        installSpec = "@aliou/pi-guardrails@0.9.5";
        version = "0.9.5";
      };
    };

    pi-preset = {
      source = {
        type = "npm";
        packageName = "@richardgill/pi-preset";
        spec = "@richardgill/pi-preset@0.0.4";
        installSpec = "@richardgill/pi-preset@0.0.8";
        version = "0.0.8";
      };
    };

    pi-prompt-template-model = {
      source = {
        type = "npm";
        packageName = "pi-prompt-template-model";
        spec = "pi-prompt-template-model@0.7.2";
        installSpec = "pi-prompt-template-model@0.10.0";
        version = "0.10.0";
      };
    };

    pi-btw = {
      source = {
        type = "npm";
        packageName = "pi-btw";
        spec = "pi-btw@0.4.1";
        installSpec = "pi-btw@0.4.1";
        version = "0.4.1";
      };
    };

    pi-gitnexus = {
      source = {
        type = "git";
        packageName = "pi-gitnexus";
        spec = "github:smantzavinos/pi-gitnexus#fa63bd3f6156cec943e42411ec0fc1909181dd2c";
        installSpec = "github:smantzavinos/pi-gitnexus#fa63bd3f6156cec943e42411ec0fc1909181dd2c";
      };
    };
  };

  enabledPiPackages = lib.filterAttrs (packageId: _: cfg.enableGitNexus || packageId != "pi-gitnexus") piPackages;
  piManagedPackageIds = builtins.attrNames enabledPiPackages;
  piRuntimePackageIds = builtins.filter (packageId: enabledPiPackages.${packageId}.source.type != "local") piManagedPackageIds;
  piManagedPackageList = map (packageId: (enabledPiPackages.${packageId} // { inherit packageId; })) piManagedPackageIds;

  visualExplainerSkill = "${visualExplainer}/plugins/visual-explainer";
  agentKitSrc = agentKit;

  piPkg = llmAgents.packages.${pkgs.system}.pi;
  checkUpdatesPkg = self.packages.${pkgs.system}.check-updates;
  piWrapperPkg = lib.hiPrio self.packages.${pkgs.system}.pi-launch-wrapper;

  guardrailsConfigPath = "${self}/nix/modules/pi/guardrails.json";

  # Repository root path for referencing skills and agents
  repoRoot = "${self}";

  piSettings = {
    defaultProvider = cfg.defaultProvider;
    defaultModel = cfg.defaultModel;
    defaultThinkingLevel = cfg.defaultThinkingLevel;
    theme = cfg.theme;
    quietStartup = false;
    hideThinkingBlock = false;

    compaction = {
      enabled = true;
      reserveTokens = 16384;
      keepRecentTokens = 20000;
    };

    thinkingBudgets = {
      low = 4096;
      medium = 8192;
      high = 32768;
    };

    enableSkillCommands = true;

    lsp = {
      hookMode = "agent_end";
    };

    enabledModels = cfg.enabledModels;

    packages = map (packageId: "./packages/${packageId}") piRuntimePackageIds;

    subagents = {
      disableBuiltins = true;
    };
  };

  piSettingsFile = pkgs.writeText "pi-settings-nix.json" (builtins.toJSON piSettings);
  piManagedPackagesFile = pkgs.writeText "pi-managed-packages.json" (builtins.toJSON {
    packages = piManagedPackageList;
  });

in
{
  options.engineering-agents.pi = {
    enable = lib.mkEnableOption "Pi coding agent with engineering-agents skills, agents, and presets";

    defaultProvider = lib.mkOption {
      type = lib.types.str;
      default = "zai-coding-plan";
      description = "Default Pi model provider";
    };

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "glm-5.2";
      description = "Default Pi model";
    };

    defaultThinkingLevel = lib.mkOption {
      type = lib.types.str;
      default = "medium";
      description = "Default thinking level";
    };

    theme = lib.mkOption {
      type = lib.types.str;
      default = "catppuccin-mocha";
      description = "Pi theme";
    };

    enabledModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "openai-codex/gpt-5.6-terra"
        "openai-codex/gpt-5.6-sol"
        "openai-codex/gpt-5.5"
        "openai-codex/gpt-5.3-codex"
        "zai-coding-plan/glm-5.2"
        "xai/grok-4.5"
        "fireworks/accounts/fireworks/models/deepseek-v4-pro"
        "fireworks/accounts/fireworks/models/kimi-k2p7-code"
        "fireworks/accounts/fireworks/models/minimax-m3"
        "fireworks/accounts/fireworks/models/qwen3p7-plus"
        "fireworks/accounts/fireworks/models/glm-5p2"
        "google-gemini-cli/gemini-3.5-flash-preview"
      ];
      description = "Models available for Ctrl+P cycling";
    };

    enableGitNexus = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable GitNexus CLI and the pi-gitnexus managed package";
    };

    enableAgentKit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install agent-kit extensions (direnv, ast-grep)";
    };

    enableVisualExplainer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install visual-explainer skill";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      checkUpdatesPkg
      piWrapperPkg
      piPkg
      pkgs.ast-grep
    ] ++ lib.optional cfg.enableGitNexus llmAgents.packages.${pkgs.system}.gitnexus;

    home.file = {
      # Keybindings
      ".pi/agent/keybindings.json".text = builtins.toJSON {
        "tui.select.up" = [ "up" "ctrl+p" ];
        "tui.select.down" = [ "down" "ctrl+n" ];
        "app.model.cycleForward" = [ "alt+]" ];
        "app.model.cycleBackward" = [ "alt+[" ];
        "app.model.select" = [ "alt+l" ];
        "app.thinking.cycle" = [ "ctrl+t" ];
        "app.thinking.toggle" = [ "ctrl+shift+t" ];
      };

      # Catppuccin Mocha theme with tmux-friendly user message colors
      ".pi/agent/themes/catppuccin-mocha.json".text = ''
        {
          "$schema": "https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json",
          "name": "catppuccin-mocha",
          "vars": {
            "rosewater": "#f5e0dc", "flamingo": "#f2cdcd", "pink": "#f5c2e7",
            "mauve": "#cba6f7", "red": "#f38ba8", "maroon": "#eba0ac",
            "peach": "#fab387", "yellow": "#f9e2af", "green": "#a6e3a1",
            "teal": "#94e2d5", "sky": "#89dceb", "sapphire": "#74c7ec",
            "blue": "#89b4fa", "lavender": "#b4befe", "text": "#cdd6f4",
            "subtext": "#a6adc8", "overlay": "#6c7086", "surface2": "#6c7086",
            "surface1": "#585b70", "surface0": "#45475a", "surface": "#313244",
            "base": "#1e1e2e", "mantle": "#181825", "crust": "#11111b"
          },
          "colors": {
            "accent": "lavender", "border": "blue", "borderAccent": "sky",
            "borderMuted": "surface0", "success": "green", "error": "red",
            "warning": "peach", "muted": "overlay", "dim": "surface2",
            "text": "text", "thinkingText": "subtext", "selectedBg": "surface",
            "userMessageBg": "surface", "userMessageText": "text",
            "customMessageBg": "surface", "customMessageText": "text",
            "customMessageLabel": "mauve", "toolPendingBg": "mantle",
            "toolSuccessBg": "#394545", "toolErrorBg": "#483346",
            "toolTitle": "lavender", "toolOutput": "subtext",
            "mdHeading": "yellow", "mdLink": "blue", "mdLinkUrl": "overlay",
            "mdCode": "peach", "mdCodeBlock": "green", "mdCodeBlockBorder": "surface1",
            "mdQuote": "overlay", "mdQuoteBorder": "surface1", "mdHr": "surface1",
            "mdListBullet": "teal", "toolDiffAdded": "green", "toolDiffRemoved": "red",
            "toolDiffContext": "overlay", "syntaxComment": "surface2",
            "syntaxKeyword": "mauve", "syntaxFunction": "blue", "syntaxVariable": "flamingo",
            "syntaxString": "green", "syntaxNumber": "peach", "syntaxType": "teal",
            "syntaxOperator": "rosewater", "syntaxPunctuation": "overlay",
            "thinkingOff": "surface0", "thinkingMinimal": "surface1",
            "thinkingLow": "blue", "thinkingMedium": "sapphire",
            "thinkingHigh": "mauve", "thinkingXhigh": "pink", "bashMode": "green"
          },
          "export": {
            "pageBg": "#11111b", "cardBg": "#181825", "infoBg": "#313244",
            "text": "#cdd6f4", "muted": "#6c7086"
          }
        }
      '';

      # Guardrails config (out-of-store symlink for runtime writes)
      ".pi/agent/extensions/guardrails.json".source =
        config.lib.file.mkOutOfStoreSymlink guardrailsConfigPath;

      # Repo-owned startup notifier extension
      ".pi/agent/extensions/startup-staleness-warning/index.ts".source =
        "${repoRoot}/nix/modules/pi/extensions/startup-staleness-warning/index.ts";

      # Agent guidance
      ".pi/agent/CODEX.md".text = ''
        ## GPT-Optimized Guidance (injected only for OpenAI Codex models)

        You are a senior, pragmatic, production-focused software engineer with 15+ years experience shipping reliable systems.

        **Core principles (always follow):**
        - Think step-by-step BEFORE any tool call or edit. Never guess file contents — read first.
        - Prefer simplicity, readability, and idiomatic code over cleverness.
        - For every non-trivial change: (1) plan, (2) implement with tools, (3) verify (run tests/build/lint), (4) reflect and fix if needed.
        - Be extremely precise with tool arguments. If unsure about a path or command, read/explore first.
        - Output format: after major edits, always summarize what changed and why in a clear bullet list.
        - If a task might take >10 tool calls, break it into verifiable milestones and confirm with me before continuing.

        **Tool-use style (OpenAI-specific):**
        - You excel at parallel tool use when safe. Group independent reads/edits.
        - For code edits, use the smallest possible targeted edit (the Edit tool loves precise hunks).
        - When reasoning is heavy, keep internal thoughts concise — the model already has strong chain-of-thought.

        **Never hallucinate completion.** If blocked or unsure, say so clearly and suggest the next best action or sub-task.

        Current stack/context will be provided below. Always respect it.
      '';

      ".pi/agent/CLAUDE.md".text = ''
        ## Claude Guidance

        You are an expert coding assistant. Follow the same principles as usual:
        - Think step-by-step before edits
        - Prefer simplicity and readability
        - Verify changes work before completing tasks
      '';

      # Provider and model definitions
      ".pi/agent/models.json".text = builtins.toJSON {
        providers = {
          zai-coding-plan = {
            apiKey = "$ZAI_API_KEY";
            baseUrl = "https://api.z.ai/api/coding/paas/v4";
            api = "openai-completions";
            models = [
              { id = "glm-5.2"; name = "GLM 5.2"; contextWindow = 1048576; maxTokens = 131072; }
              { id = "glm-5.1"; name = "GLM 5.1"; contextWindow = 204800; maxTokens = 131072; }
              { id = "glm-5"; name = "GLM 5"; contextWindow = 204800; maxTokens = 131072; }
              { id = "glm-4.7"; name = "GLM 4.7"; contextWindow = 204800; maxTokens = 131072; }
              { id = "glm-4.7-flash"; name = "GLM 4.7 Flash"; contextWindow = 131072; maxTokens = 8192; }
              { id = "glm-4.6v"; name = "GLM 4.6 Vision"; contextWindow = 131072; maxTokens = 16384; input = [ "text" "image" ]; }
              { id = "glm-4.5v"; name = "GLM 4.5 Vision"; contextWindow = 131072; maxTokens = 16384; input = [ "text" "image" ]; }
              { id = "glm-4.6"; name = "GLM 4.6"; contextWindow = 131072; maxTokens = 16384; }
              { id = "glm-4.5"; name = "GLM 4.5"; contextWindow = 131072; maxTokens = 16384; }
              { id = "glm-4.5-air"; name = "GLM 4.5 Air"; contextWindow = 131072; maxTokens = 8192; }
              { id = "glm-4.5-flash"; name = "GLM 4.5 Flash"; contextWindow = 131072; maxTokens = 8192; }
            ];
          };
        };
      };

      # MCP server configuration
      ".pi/agent/mcp.json".text = builtins.toJSON {
        mcpServers = {
          "web-search-prime" = {
            type = "http";
            url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
            headers = { Authorization = "Bearer {env:ZAI_API_KEY}"; };
            lifecycle = "lazy";
            idleTimeout = 10;
          };
          "web-reader" = {
            type = "http";
            url = "https://api.z.ai/api/mcp/web_reader/mcp";
            headers = { Authorization = "Bearer {env:ZAI_API_KEY}"; };
            lifecycle = "lazy";
            idleTimeout = 10;
          };
          "zread" = {
            type = "http";
            url = "https://api.z.ai/api/mcp/zread/mcp";
            headers = { Authorization = "Bearer {env:ZAI_API_KEY}"; };
            lifecycle = "lazy";
            idleTimeout = 10;
          };
          "zai-vision" = {
            command = "npx";
            args = [ "-y" "@z_ai/mcp-server" ];
            env = {
              Z_AI_API_KEY = "{env:ZAI_API_KEY}";
              Z_AI_MODE = "ZAI";
            };
            lifecycle = "lazy";
            enabled = false;
          };
        };
        settings = {
          toolPrefix = "server";
          idleTimeout = 10;
        };
      };

      # ============================================================
      # Engineering workflow skills
      # ============================================================
      ".pi/agent/skills/discovery".source = "${repoRoot}/dist/skills/pi/discovery";
      ".pi/agent/skills/design".source = "${repoRoot}/dist/skills/pi/design";
      ".pi/agent/skills/research".source = "${repoRoot}/dist/skills/pi/research";
      ".pi/agent/skills/create-plan".source = "${repoRoot}/dist/skills/pi/create-plan";
      ".pi/agent/skills/review-plan".source = "${repoRoot}/dist/skills/pi/review-plan";
      ".pi/agent/skills/create-worklog".source = "${repoRoot}/dist/skills/pi/create-worklog";
      ".pi/agent/skills/execute-task".source = "${repoRoot}/dist/skills/pi/execute-task";
      ".pi/agent/skills/execution-orchestrator".source = "${repoRoot}/dist/skills/pi/execution-orchestrator";
      ".pi/agent/skills/review-code".source = "${repoRoot}/dist/skills/pi/review-code";
      ".pi/agent/skills/review-approach".source = "${repoRoot}/dist/skills/pi/review-approach";
      ".pi/agent/skills/assess-repo".source = "${repoRoot}/dist/skills/pi/assess-repo";
      ".pi/agent/skills/create-skills".source = "${repoRoot}/dist/skills/pi/create-skills";
      ".pi/agent/skills/configure-pi".source = "${repoRoot}/dist/skills/pi/configure-pi";
      ".pi/agent/skills/create-new-repo-docs".source = "${repoRoot}/dist/skills/pi/create-new-repo-docs";

      # ============================================================
      # Agent definitions
      # ============================================================
      ".pi/agent/agents/planner.md".source = "${repoRoot}/agents/planner.md";
      ".pi/agent/agents/plan-reviewer.md".source = "${repoRoot}/agents/plan-reviewer.md";
      ".pi/agent/agents/code-reviewer.md".source = "${repoRoot}/agents/code-reviewer.md";
      ".pi/agent/agents/worker.md".source = "${repoRoot}/agents/worker.md";
      ".pi/agent/agents/ui-worker.md".source = "${repoRoot}/agents/ui-worker.md";
      ".pi/agent/agents/researcher.md".source = "${repoRoot}/agents/researcher.md";
      ".pi/agent/agents/vision.md".source = "${repoRoot}/agents/vision.md";
      ".pi/agent/agents/oracle.md".source = "${repoRoot}/agents/oracle.md";

      # Preset configuration
      ".pi/agent/preset.jsonc".source = "${repoRoot}/agents/preset.jsonc";
    };

    # ============================================================
    # Activation Scripts
    # ============================================================
    home.activation = {
      installPiSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        SETTINGS_FILE="$HOME/.pi/agent/settings.json"
        NIX_SETTINGS="${piSettingsFile}"
        mkdir -p "$(dirname "$SETTINGS_FILE")"

        if [ -f "$SETTINGS_FILE" ]; then
          ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$SETTINGS_FILE" "$NIX_SETTINGS" > "$SETTINGS_FILE.tmp" \
            && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
          echo "Merged Nix settings into $SETTINGS_FILE"
        else
          cp "$NIX_SETTINGS" "$SETTINGS_FILE"
          chmod 644 "$SETTINGS_FILE"
          echo "Created $SETTINGS_FILE from Nix defaults"
        fi

        rm -f "$SETTINGS_FILE.backup" "$SETTINGS_FILE.bak"
      '';

      installPiExtensions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        MANAGED_PACKAGES_FILE="${piManagedPackagesFile}"
        COMPILER_HELPER="${self}/nix/modules/pi/compile-managed-packages.mjs"
        INSTALL_STATE_HELPER="${self}/nix/modules/pi/build-managed-package-install-state.mjs"
        DECLARATIONS_PATH="$HOME/.pi/agent/managed-packages.declarations.json"
        COMPILE_REPORT_PATH="$HOME/.pi/agent/managed-packages.report.json"
        INSTALL_STATE_PATH="$HOME/.pi/agent/managed-packages.install-state.json"

        mkdir -p "$HOME/.pi/agent/extensions"
        mkdir -p "$HOME/.pi/agent/skills"
        mkdir -p "$HOME/.pi/agent/prompts"
        mkdir -p "$HOME/.pi/agent/agents"
        mkdir -p "$HOME/.pi/agent/packages"
        mkdir -p "$HOME/.pi/agent/sources"

        export PATH="${pkgs.nodejs}/bin:${pkgs.git}/bin:${pkgs.python3}/bin:${pkgs.gcc}/bin:${pkgs.gnumake}/bin:$PATH"
        export NPM_CONFIG_PREFIX="$HOME/.pi/packages"
        mkdir -p "$HOME/.pi/packages"

        normalize_git_remote_url() {
          local install_spec="$1"
          local repo_spec="''${install_spec%%#*}"

          case "$repo_spec" in
            github:*)
              printf 'https://github.com/%s.git\n' "''${repo_spec#github:}"
              ;;
            git+https://*|git+http://*)
              printf '%s\n' "''${repo_spec#git+}"
              ;;
            https://*|http://*|git://*|ssh://*|git@*)
              printf '%s\n' "$repo_spec"
              ;;
            *)
              return 1
              ;;
          esac
        }

        resolve_git_install_metadata() {
          local install_spec="$1"
          local requested_ref=""
          local requested_ref_type="default"
          local remote_url
          local ls_remote
          local commit=""
          local branch_commit=""
          local tag_commit=""

          if [[ "$install_spec" == *#* ]]; then
            requested_ref="''${install_spec#*#}"
          fi

          if [[ -n "$requested_ref" && "$requested_ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
            printf '%s\tcommit\n' "$requested_ref"
            return 0
          fi

          if [[ -n "$requested_ref" && "$requested_ref" == semver:* ]]; then
            requested_ref_type="semver"
          fi

          remote_url="$(normalize_git_remote_url "$install_spec")" || return 1
          ls_remote="$(${pkgs.git}/bin/git ls-remote --symref "$remote_url" HEAD 'refs/heads/*' 'refs/tags/*' 'refs/tags/*^{}')" || return 1

          if [[ -z "$requested_ref" ]]; then
            commit="$(printf '%s\n' "$ls_remote" | ${pkgs.gawk}/bin/awk '$2 == "HEAD" { print $1; exit }')"
          elif [[ "$requested_ref_type" == "semver" ]]; then
            commit="$(printf '%s\n' "$ls_remote" | ${pkgs.gawk}/bin/awk -v tag_ref="refs/tags/$requested_ref" -v peeled_tag_ref="refs/tags/$requested_ref^{}" '$2 == peeled_tag_ref || $2 == tag_ref { print $1; exit }')"
          else
            branch_commit="$(printf '%s\n' "$ls_remote" | ${pkgs.gawk}/bin/awk -v branch_ref="refs/heads/$requested_ref" '$2 == branch_ref { print $1; exit }')"
            tag_commit="$(printf '%s\n' "$ls_remote" | ${pkgs.gawk}/bin/awk -v tag_ref="refs/tags/$requested_ref" -v peeled_tag_ref="refs/tags/$requested_ref^{}" '$2 == peeled_tag_ref || $2 == tag_ref { print $1; exit }')"

            if [[ -n "$branch_commit" ]]; then
              commit="$branch_commit"
              requested_ref_type="branch"
            elif [[ -n "$tag_commit" ]]; then
              commit="$tag_commit"
              requested_ref_type="tag"
            fi
          fi

          if [[ -z "$commit" ]]; then
            return 1
          fi

          printf '%s\t%s\n' "$commit" "$requested_ref_type"
        }

        echo "Installing managed Pi package sources..."

        INSTALLED_JSON=$(npm list -g --depth=0 --json 2>/dev/null || echo '{}')

        ${pkgs.jq}/bin/jq -r '
          [.packages[] | select(.source.type == "npm")]
          | unique_by([.source.packageName, .source.installSpec] | @json)
          | .[]
          | [.source.packageName, .source.version, .source.installSpec]
          | @tsv
        ' "$MANAGED_PACKAGES_FILE" |
        while IFS=$'\t' read -r package_name package_version install_spec; do
          if echo "$INSTALLED_JSON" | ${pkgs.jq}/bin/jq -e --arg package_name "$package_name" --arg package_version "$package_version" '.dependencies[$package_name].version == $package_version' >/dev/null 2>&1; then
            echo "Skipping $package_name@$package_version (already installed)"
          else
            echo "Installing $install_spec..."
            npm install -g "$install_spec" 2>&1 || echo "Warning: $install_spec install failed"
          fi
        done

        ${pkgs.jq}/bin/jq -r '
          [.packages[] | select(.source.type == "git")]
          | unique_by([.source.packageName, .source.installSpec] | @json)
          | .[]
          | [.source.packageName, .source.installSpec]
          | @tsv
        ' "$MANAGED_PACKAGES_FILE" |
        while IFS=$'\t' read -r package_name install_spec; do
          package_dir="$HOME/.pi/packages/lib/node_modules/$package_name"
          local_metadata_path="$package_dir/.pi-managed-install.json"

          # Resolve the commit this spec should install to. For a 40-hex commit
          # spec this is a pure comparison (no network); for a branch/tag/semver
          # ref it performs a single `git ls-remote` to find the current target.
          git_metadata="$(resolve_git_install_metadata "$install_spec")" || {
            echo "Failed to resolve git metadata for $package_name ($install_spec)" >&2
            exit 1
          }
          IFS=$'\t' read -r target_commit requested_ref_type <<< "$git_metadata"

          # Skip the expensive uninstall/reinstall when the resolved commit
          # already matches what is installed (mirrors the npm version gate).
          needs_install=1
          if [ -d "$package_dir" ] && [ -f "$local_metadata_path" ]; then
            current_commit="$(${pkgs.jq}/bin/jq -r '.installedCommit // ""' "$local_metadata_path" 2>/dev/null || echo "")"
            if [ "$current_commit" = "$target_commit" ]; then
              echo "Skipping $package_name (already at $target_commit)"
              needs_install=0
            fi
          fi

          if [ "$needs_install" = "1" ]; then
            echo "Installing $package_name from $install_spec (git source)..."
            npm uninstall -g "$package_name" >/dev/null 2>&1 || true
            rm -rf "$package_dir"
            npm install -g --install-links --legacy-peer-deps "$install_spec" 2>&1
          fi

          # Always refresh the install metadata (even on the skip path) so a
          # changed ref *type* at the same commit (e.g. branch -> pinned commit)
          # is reflected in the install-state and staleness reporting. Guarded
          # on the package dir so a failed install does not leave orphan metadata.
          if [ -d "$package_dir" ]; then
            cat > "$local_metadata_path" <<EOF
{
  "schemaVersion": 1,
  "installedCommit": "$target_commit",
  "requestedRefType": "$requested_ref_type"
}
EOF
          fi
        done

        ${pkgs.jq}/bin/jq --arg materialized_prefix "$HOME/.pi/packages/lib/node_modules/" '
          {
            packages: [
              .packages[]
              | ({
                  packageId,
                  source: (
                    if .source.type == "local" then
                      {
                        type: .source.type,
                        spec: .source.spec,
                        installSpec: (.source.installSpec // .source.spec),
                        packageName: .source.packageName
                      }
                    else
                      {
                        type: .source.type,
                        spec: .source.spec,
                        installSpec: (.source.installSpec // .source.spec),
                        packageName: .source.packageName,
                        materializedPath: ($materialized_prefix + .source.packageName)
                      }
                    end
                  )
                } + if has("expose") then { expose: .expose } else {} end)
            ]
          }
        ' "$MANAGED_PACKAGES_FILE" > "$DECLARATIONS_PATH"

        node "$COMPILER_HELPER" --declarations "$DECLARATIONS_PATH" --output-dir "$HOME/.pi/agent" > "$COMPILE_REPORT_PATH"
        node "$INSTALL_STATE_HELPER" --declarations "$DECLARATIONS_PATH" > "$INSTALL_STATE_PATH"

        ${pkgs.jq}/bin/jq -r '.warnings[]? | "[\(.code)] \(.message)"' "$COMPILE_REPORT_PATH"

        rm -rf /tmp/jiti

        ${pkgs.jq}/bin/jq -r '.packages[].source.packageName' "$MANAGED_PACKAGES_FILE" |
        while IFS= read -r package_name; do
          if [ -d "$HOME/.pi/agent/extensions/$package_name" ]; then
            echo "Removing duplicate extension: $package_name"
            rm -rf "$HOME/.pi/agent/extensions/$package_name"
          fi
        done

        echo "managed Pi package installation complete"
      '';

      installVisualExplainer = lib.mkIf cfg.enableVisualExplainer (lib.hm.dag.entryAfter [ "writeBoundary" "installPiExtensions" ] ''
        VISUAL_EXPLAINER_DIR="$HOME/.pi/agent/skills/visual-explainer"

        echo "Installing visual-explainer skill from pinned source..."
        rm -rf "$VISUAL_EXPLAINER_DIR"
        mkdir -p "$(dirname "$VISUAL_EXPLAINER_DIR")"
        cp -r ${visualExplainerSkill} "$VISUAL_EXPLAINER_DIR"
        chmod -R u+w "$VISUAL_EXPLAINER_DIR"

        # Slash-command prompts ship under commands/ in the upstream skill.
        if [ -d "$VISUAL_EXPLAINER_DIR/commands" ]; then
          mkdir -p "$HOME/.pi/agent/prompts"
          cp "$VISUAL_EXPLAINER_DIR/commands/"*.md "$HOME/.pi/agent/prompts/" 2>/dev/null || true
        fi

        echo "visual-explainer installed"
      '');

      installAgentKit = lib.mkIf cfg.enableAgentKit (lib.hm.dag.entryAfter [ "writeBoundary" "installPiExtensions" ] ''
        DIRENV_EXT="$HOME/.pi/agent/extensions/direnv"
        AST_GREP_EXT="$HOME/.pi/agent/extensions/ast-grep"
        AST_GREP_SKILL="$HOME/.pi/agent/skills/ast-grep"

        echo "Installing agent-kit extensions and skills from pinned source..."
        mkdir -p "$HOME/.pi/agent/extensions"

        rm -rf "$DIRENV_EXT"
        mkdir -p "$DIRENV_EXT"
        ln -sf ${agentKitSrc}/extensions/direnv/direnv.ts "$DIRENV_EXT/index.ts"

        rm -rf "$AST_GREP_EXT"
        mkdir -p "$AST_GREP_EXT"
        ln -sf ${agentKitSrc}/extensions/ast-grep/ast-grep.ts "$AST_GREP_EXT/index.ts"

        rm -rf "$AST_GREP_SKILL"
        ln -sf ${agentKitSrc}/skills/ast-grep "$AST_GREP_SKILL"

        echo "agent-kit extensions and skills installed"
      '');
    };

    home.sessionVariables = {
      NPM_CONFIG_PREFIX = "$HOME/.pi/packages";
    };
  };
}
