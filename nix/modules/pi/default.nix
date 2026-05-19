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
{ self, llmAgents }:

{ config, lib, pkgs, ... }:

let
  cfg = config.engineering-agents.pi;

  # Managed Pi package declarations
  piPackages = {
    pi-subagents = {
      source = {
        type = "git";
        packageName = "pi-subagents";
        spec = "github:smantzavinos/pi-subagents#feat/agent-overrides-all-sources";
        installSpec = "github:smantzavinos/pi-subagents#feat/agent-overrides-all-sources";
      };
    };

    pi-hooks = {
      source = {
        type = "git";
        packageName = "pi-hooks";
        spec = "github:smantzavinos/pi-hooks";
        installSpec = "github:smantzavinos/pi-hooks";
      };
    };

    pi-agent-guidance = {
      source = {
        type = "npm";
        packageName = "@tmustier/pi-agent-guidance";
        spec = "@tmustier/pi-agent-guidance@0.1.3";
        installSpec = "@tmustier/pi-agent-guidance@0.1.3";
        version = "0.1.3";
      };
    };

    pi-mcp-adapter = {
      source = {
        type = "npm";
        packageName = "pi-mcp-adapter";
        spec = "pi-mcp-adapter@2.2.2";
        installSpec = "pi-mcp-adapter@2.2.2";
        version = "2.2.2";
      };
    };

    pi-web-access = {
      source = {
        type = "npm";
        packageName = "pi-web-access";
        spec = "pi-web-access@0.10.6";
        installSpec = "pi-web-access@0.10.6";
        version = "0.10.6";
      };
    };

    pi-powerline-footer = {
      source = {
        type = "npm";
        packageName = "pi-powerline-footer";
        spec = "pi-powerline-footer@0.4.9";
        installSpec = "pi-powerline-footer@0.4.9";
        version = "0.4.9";
      };
    };

    pi-interactive-shell = {
      source = {
        type = "npm";
        packageName = "pi-interactive-shell";
        spec = "pi-interactive-shell@0.10.7";
        installSpec = "pi-interactive-shell@0.10.7";
        version = "0.10.7";
      };
    };

    pi-subdir-context = {
      source = {
        type = "npm";
        packageName = "pi-subdir-context";
        spec = "pi-subdir-context@1.1.2";
        installSpec = "pi-subdir-context@1.1.2";
        version = "1.1.2";
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
        installSpec = "pi-notify@1.3.0";
        version = "1.3.0";
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

    catppuccin-mocha = {
      source = {
        type = "npm";
        packageName = "@ujjwalgrover/pi-catppuccin";
        spec = "@ujjwalgrover/pi-catppuccin@1.0.0";
        installSpec = "@ujjwalgrover/pi-catppuccin@1.0.0";
        version = "1.0.0";
      };
      expose = {
        themes = [ "catppuccin-mocha" ];
      };
    };

    pi-ext-leader-key = {
      source = {
        type = "git";
        packageName = "pi-ext";
        spec = "github:tomsej/pi-ext#515352c80bc1ee7e22ed08add915efa220c4c822";
        installSpec = "github:tomsej/pi-ext#515352c80bc1ee7e22ed08add915efa220c4c822";
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
        spec = "github:tomsej/pi-ext#515352c80bc1ee7e22ed08add915efa220c4c822";
        installSpec = "github:tomsej/pi-ext#515352c80bc1ee7e22ed08add915efa220c4c822";
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
        installSpec = "@richardgill/pi-preset@0.0.4";
        version = "0.0.4";
      };
    };

    pi-prompt-template-model = {
      source = {
        type = "npm";
        packageName = "pi-prompt-template-model";
        spec = "pi-prompt-template-model@0.7.2";
        installSpec = "pi-prompt-template-model@0.7.2";
        version = "0.7.2";
      };
    };

    pi-btw = {
      source = {
        type = "npm";
        packageName = "pi-btw";
        spec = "pi-btw@0.2.1";
        installSpec = "pi-btw@0.2.1";
        version = "0.2.1";
      };
    };

    pi-gitnexus = {
      source = {
        type = "git";
        packageName = "pi-gitnexus";
        spec = "github:smantzavinos/pi-gitnexus#fix/session-shutdown-cleanup";
        installSpec = "github:smantzavinos/pi-gitnexus#fix/session-shutdown-cleanup";
      };
    };
  };

  piManagedPackageIds = builtins.attrNames piPackages;
  piRuntimePackageIds = builtins.filter (packageId: piPackages.${packageId}.source.type != "local") piManagedPackageIds;
  piManagedPackageList = map (packageId: (piPackages.${packageId} // { inherit packageId; })) piManagedPackageIds;

  visualExplainerRepo = "https://github.com/nicobailon/visual-explainer.git";
  agentKitRepo = "https://github.com/aldoborrero/agent-kit.git";
  agentKitRev = "16b100a70195852b291720e7213eed51c714d230";

  piPkg = llmAgents.packages.${pkgs.system}.pi;

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
      default = "glm-5";
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
        "openai-codex/gpt-5.5"
        "openai-codex/gpt-5.4"
        "openai-codex/gpt-5.3-codex"
        "zai-coding-plan/glm-5.1"
        "zai-coding-plan/glm-5"
        "zai-coding-plan/glm-4.7"
        "fireworks/accounts/fireworks/models/deepseek-v4-pro"
        "fireworks/accounts/fireworks/models/kimi-k2p6"
        "fireworks/accounts/fireworks/models/minimax-m2p7"
        "fireworks/accounts/fireworks/models/qwen3p6-plus"
        "fireworks/accounts/fireworks/models/gemma-4-26b-a4b-it"
        "google-gemini-cli/gemini-3-flash-preview"
        "google-gemini-cli/gemini-3.1-pro-preview"
      ];
      description = "Models available for Ctrl+P cycling";
    };

    enableGitNexus = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install GitNexus knowledge graph CLI";
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
            apiKey = "ZAI_API_KEY";
            baseUrl = "https://api.z.ai/api/coding/paas/v4";
            api = "openai-completions";
            models = [
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
          fireworks = {
            apiKey = "FIREWORKS_API_KEY";
            baseUrl = "https://api.fireworks.ai/inference/v1";
            api = "openai-completions";
            models = [
              { id = "accounts/fireworks/models/kimi-k2p6"; name = "Kimi K2.6"; contextWindow = 262144; maxTokens = 32768; input = [ "text" "image" ]; }
              { id = "accounts/fireworks/models/deepseek-v4-pro"; name = "DeepSeek V4 Pro"; contextWindow = 1048576; maxTokens = 131072; }
              { id = "accounts/fireworks/models/minimax-m2p7"; name = "MiniMax M2.7"; contextWindow = 196608; maxTokens = 24576; }
              { id = "accounts/fireworks/models/qwen3p6-plus"; name = "Qwen 3.6 Plus"; contextWindow = 262144; maxTokens = 4000; input = [ "text" "image" ]; }
              { id = "accounts/fireworks/models/gemma-4-26b-a4b-it"; name = "Gemma 4 26B"; contextWindow = 262144; maxTokens = 8192; input = [ "text" "image" ]; }
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
      ".pi/agent/skills/discovery".source = "${repoRoot}/skills/discovery";
      ".pi/agent/skills/design".source = "${repoRoot}/skills/design";
      ".pi/agent/skills/research".source = "${repoRoot}/skills/research";
      ".pi/agent/skills/create-plan".source = "${repoRoot}/skills/create-plan";
      ".pi/agent/skills/review-plan".source = "${repoRoot}/skills/review-plan";
      ".pi/agent/skills/create-worklog".source = "${repoRoot}/skills/create-worklog";
      ".pi/agent/skills/execute-task".source = "${repoRoot}/skills/execute-task";
      ".pi/agent/skills/execution-orchestrator".source = "${repoRoot}/skills/execution-orchestrator";
      ".pi/agent/skills/review-code".source = "${repoRoot}/skills/review-code";
      ".pi/agent/skills/review-approach".source = "${repoRoot}/skills/review-approach";
      ".pi/agent/skills/assess-repo".source = "${repoRoot}/skills/assess-repo";
      ".pi/agent/skills/create-skills".source = "${repoRoot}/skills/create-skills";
      ".pi/agent/skills/create-new-repo-docs".source = "${repoRoot}/skills/create-new-repo-docs";

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
        DECLARATIONS_PATH="$HOME/.pi/agent/managed-packages.declarations.json"
        COMPILE_REPORT_PATH="$HOME/.pi/agent/managed-packages.report.json"

        mkdir -p "$HOME/.pi/agent/extensions"
        mkdir -p "$HOME/.pi/agent/skills"
        mkdir -p "$HOME/.pi/agent/prompts"
        mkdir -p "$HOME/.pi/agent/agents"
        mkdir -p "$HOME/.pi/agent/packages"
        mkdir -p "$HOME/.pi/agent/sources"

        export PATH="${pkgs.nodejs}/bin:${pkgs.git}/bin:${pkgs.python3}/bin:${pkgs.gcc}/bin:${pkgs.gnumake}/bin:$PATH"
        export NPM_CONFIG_PREFIX="$HOME/.pi/packages"
        mkdir -p "$HOME/.pi/packages"

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
          echo "Installing $package_name from $install_spec (git source)..."
          npm uninstall -g "$package_name" >/dev/null 2>&1 || true
          rm -rf "$HOME/.pi/packages/lib/node_modules/$package_name"
          npm install -g --install-links --legacy-peer-deps "$install_spec" 2>&1
        done

        ${pkgs.jq}/bin/jq --arg materialized_prefix "$HOME/.pi/packages/lib/node_modules/" '
          {
            packages: [
              .packages[]
              | ({
                  packageId,
                  source: (
                    if .source.type == "local" then
                      { type: .source.type, spec: .source.spec }
                    else
                      { type: .source.type, spec: .source.spec, materializedPath: ($materialized_prefix + .source.packageName) }
                    end
                  )
                } + if has("expose") then { expose: .expose } else {} end)
            ]
          }
        ' "$MANAGED_PACKAGES_FILE" > "$DECLARATIONS_PATH"

        node "$COMPILER_HELPER" --declarations "$DECLARATIONS_PATH" --output-dir "$HOME/.pi/agent" > "$COMPILE_REPORT_PATH"

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

        if [ ! -d "$VISUAL_EXPLAINER_DIR" ]; then
          echo "Cloning visual-explainer skill..."
          ${pkgs.git}/bin/git clone ${visualExplainerRepo} "$VISUAL_EXPLAINER_DIR"
        else
          echo "Updating visual-explainer skill..."
          (cd "$VISUAL_EXPLAINER_DIR" && ${pkgs.git}/bin/git pull --rebase) || echo "Warning: visual-explainer update failed"
        fi

        if [ -d "$VISUAL_EXPLAINER_DIR/prompts" ]; then
          mkdir -p "$HOME/.pi/agent/prompts"
          cp -r "$VISUAL_EXPLAINER_DIR/prompts/"*.md "$HOME/.pi/agent/prompts/" 2>/dev/null || true
        fi

        echo "visual-explainer installed"
      '');

      installAgentKit = lib.mkIf cfg.enableAgentKit (lib.hm.dag.entryAfter [ "writeBoundary" "installPiExtensions" ] ''
        AGENT_KIT_DIR="$HOME/.pi/agent/repos/agent-kit"
        DIRENV_EXT="$HOME/.pi/agent/extensions/direnv"
        AST_GREP_EXT="$HOME/.pi/agent/extensions/ast-grep"

        if [ ! -d "$AGENT_KIT_DIR" ]; then
          echo "Cloning agent-kit repository..."
          ${pkgs.git}/bin/git clone ${agentKitRepo} "$AGENT_KIT_DIR"
          (cd "$AGENT_KIT_DIR" && ${pkgs.git}/bin/git checkout ${agentKitRev})
        else
          CURRENT_REV=$(cd "$AGENT_KIT_DIR" && ${pkgs.git}/bin/git rev-parse HEAD)
          if [ "$CURRENT_REV" != "${agentKitRev}" ]; then
            echo "Updating agent-kit to pinned commit ${agentKitRev}..."
            (cd "$AGENT_KIT_DIR" && ${pkgs.git}/bin/git fetch origin && ${pkgs.git}/bin/git checkout ${agentKitRev})
          else
            echo "agent-kit already at pinned commit ${agentKitRev}"
          fi
        fi

        mkdir -p "$HOME/.pi/agent/extensions"
        rm -rf "$DIRENV_EXT"
        mkdir -p "$DIRENV_EXT"
        ln -sf "$AGENT_KIT_DIR/pi/extensions/direnv/direnv.ts" "$DIRENV_EXT/index.ts"

        rm -rf "$AST_GREP_EXT"
        mkdir -p "$AST_GREP_EXT"
        ln -sf "$AGENT_KIT_DIR/pi/extensions/ast-grep/ast-grep.ts" "$AST_GREP_EXT/index.ts"

        AST_GREP_SKILL="$HOME/.pi/agent/skills/ast-grep"
        rm -rf "$AST_GREP_SKILL"
        ln -sf "$AGENT_KIT_DIR/skills/ast-grep" "$AST_GREP_SKILL"

        echo "agent-kit extensions and skills installed"
      '');
    };

    home.sessionVariables = {
      NPM_CONFIG_PREFIX = "$HOME/.pi/packages";
    };
  };
}
