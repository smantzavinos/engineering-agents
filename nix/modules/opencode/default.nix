# OpenCode CLI Home Manager module
#
# Declarative configuration for OpenCode and its plugins.
# OpenCode auto-manages npm dependencies.
#
# Usage in your home-manager config:
#   imports = [ engineering-agents.homeManagerModules.opencode ];
#   engineering-agents.opencode.enable = true;
#
{ self, llmAgents }:

{ config, lib, pkgs, ... }:

let
  cfg = config.engineering-agents.opencode;

  # Pin plugin versions for reproducibility
  ohMyOpenAgentVersion = "4.8.1";
  openaiCodexAuthVersion = "4.4.0";
  opencodeIgnoreVersion = "1.1.0";
  opencodeDirenvVersion = "2025.1211.9";
  opencodeMdTableFormatterVersion = "0.0.6";

  repoRoot = "${self}";

  openaiBaseOptions = {
    include = [ "reasoning.encrypted_content" ];
    store = false;
  };

  openaiReasoningVariants = {
    none = { reasoningEffort = "none"; reasoningSummary = "auto"; textVerbosity = "medium"; };
    low = { reasoningEffort = "low"; reasoningSummary = "auto"; textVerbosity = "medium"; };
    medium = { reasoningEffort = "medium"; reasoningSummary = "auto"; textVerbosity = "medium"; };
    high = { reasoningEffort = "high"; reasoningSummary = "detailed"; textVerbosity = "medium"; };
    xhigh = { reasoningEffort = "xhigh"; reasoningSummary = "detailed"; textVerbosity = "medium"; };
  };

  openaiLegacyReasoningVariants = {
    none = { reasoningEffort = "none"; reasoningSummary = "auto"; textVerbosity = "medium"; };
    low = { reasoningEffort = "low"; reasoningSummary = "auto"; textVerbosity = "low"; };
    medium = { reasoningEffort = "medium"; reasoningSummary = "auto"; textVerbosity = "medium"; };
    high = { reasoningEffort = "high"; reasoningSummary = "detailed"; textVerbosity = "high"; };
  };

  openaiCodexReasoningVariants = {
    low = { reasoningEffort = "low"; reasoningSummary = "auto"; textVerbosity = "medium"; };
    medium = { reasoningEffort = "medium"; reasoningSummary = "auto"; textVerbosity = "medium"; };
    high = { reasoningEffort = "high"; reasoningSummary = "detailed"; textVerbosity = "medium"; };
    xhigh = { reasoningEffort = "xhigh"; reasoningSummary = "detailed"; textVerbosity = "medium"; };
  };

  openaiCodexMiniReasoningVariants = {
    medium = { reasoningEffort = "medium"; reasoningSummary = "auto"; textVerbosity = "medium"; };
    high = { reasoningEffort = "high"; reasoningSummary = "detailed"; textVerbosity = "medium"; };
  };

  openaiModel = name: variants: {
    inherit name variants;
    limit = { context = 272000; output = 128000; };
    modalities = { input = [ "text" "image" ]; output = [ "text" ]; };
  };

  # ChatGPT Plus/Pro quota models provided by opencode-openai-codex-auth.
  # Keep this aligned with that plugin's config/opencode-modern.json.
  openaiOAuthModels = {
    "gpt-5.5" = openaiModel "GPT 5.5 (ChatGPT Pro OAuth)" openaiReasoningVariants;
    "gpt-5.2" = openaiModel "GPT 5.2 (ChatGPT Pro OAuth)" openaiReasoningVariants;
    "gpt-5.2-codex" = openaiModel "GPT 5.2 Codex (ChatGPT Pro OAuth)" openaiCodexReasoningVariants;
    "gpt-5.1-codex-max" = openaiModel "GPT 5.1 Codex Max (ChatGPT Pro OAuth)" openaiCodexReasoningVariants;
    "gpt-5.1-codex" = openaiModel "GPT 5.1 Codex (ChatGPT Pro OAuth)" {
      low = { reasoningEffort = "low"; reasoningSummary = "auto"; textVerbosity = "medium"; };
      medium = { reasoningEffort = "medium"; reasoningSummary = "auto"; textVerbosity = "medium"; };
      high = { reasoningEffort = "high"; reasoningSummary = "detailed"; textVerbosity = "medium"; };
    };
    "gpt-5.1-codex-mini" = openaiModel "GPT 5.1 Codex Mini (ChatGPT Pro OAuth)" openaiCodexMiniReasoningVariants;
    "gpt-5.1" = openaiModel "GPT 5.1 (ChatGPT Pro OAuth)" openaiLegacyReasoningVariants;
  };

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

    xdg.configFile = {
      "opencode/opencode.json".text = builtins.toJSON {
        "$schema" = "https://opencode.ai/config.json";
        model = cfg.model;

        plugin = [
          "oh-my-openagent@${ohMyOpenAgentVersion}"
          "opencode-openai-codex-auth@${openaiCodexAuthVersion}"
          "opencode-ignore@${opencodeIgnoreVersion}"
          "@simonwjackson/opencode-direnv@${opencodeDirenvVersion}"
          "@franlol/opencode-md-table-formatter@${opencodeMdTableFormatterVersion}"
        ];

        provider = {
          google = {
            models = {
              "gemini-3-pro-high" = {
                name = "Gemini 3 Pro High";
                limit = { context = 1048576; output = 65535; };
                modalities = { input = [ "text" "image" "pdf" ]; output = [ "text" ]; };
              };
              "gemini-3-pro-low" = {
                name = "Gemini 3 Pro Low";
                limit = { context = 1048576; output = 65535; };
                modalities = { input = [ "text" "image" "pdf" ]; output = [ "text" ]; };
              };
              "gemini-3-flash" = {
                name = "Gemini 3 Flash";
                limit = { context = 1048576; output = 65536; };
                modalities = { input = [ "text" "image" "pdf" ]; output = [ "text" ]; };
              };
              "claude-sonnet-4-5" = {
                name = "Claude Sonnet 4.5";
                limit = { context = 200000; output = 64000; };
                modalities = { input = [ "text" "image" "pdf" ]; output = [ "text" ]; };
              };
              "claude-sonnet-4-5-thinking-low" = {
                name = "Claude Sonnet 4.5 Thinking Low";
                limit = { context = 200000; output = 64000; };
                modalities = { input = [ "text" "image" "pdf" ]; output = [ "text" ]; };
              };
              "claude-sonnet-4-5-thinking-medium" = {
                name = "Claude Sonnet 4.5 Thinking Medium";
                limit = { context = 200000; output = 64000; };
                modalities = { input = [ "text" "image" "pdf" ]; output = [ "text" ]; };
              };
              "claude-sonnet-4-5-thinking-high" = {
                name = "Claude Sonnet 4.5 Thinking High";
                limit = { context = 200000; output = 64000; };
                modalities = { input = [ "text" "image" "pdf" ]; output = [ "text" ]; };
              };
              "claude-opus-4-5-thinking-low" = {
                name = "Claude Opus 4.5 Thinking Low";
                limit = { context = 200000; output = 64000; };
                modalities = { input = [ "text" "image" "pdf" ]; output = [ "text" ]; };
              };
              "claude-opus-4-5-thinking-medium" = {
                name = "Claude Opus 4.5 Thinking Medium";
                limit = { context = 200000; output = 64000; };
                modalities = { input = [ "text" "image" "pdf" ]; output = [ "text" ]; };
              };
              "claude-opus-4-5-thinking-high" = {
                name = "Claude Opus 4.5 Thinking High";
                limit = { context = 200000; output = 64000; };
                modalities = { input = [ "text" "image" "pdf" ]; output = [ "text" ]; };
              };
            };
          };

          # `openai` is reserved for ChatGPT Plus/Pro OAuth via
          # opencode-openai-codex-auth. The plugin is hard-coded to this
          # provider ID and skips itself when API-key auth is selected.
          openai = {
            options = openaiBaseOptions;
            models = openaiOAuthModels;
          };

        };

        mcp = {
          "web-search-prime" = {
            type = "remote";
            url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
            oauth = false;
            headers = { Authorization = "Bearer {env:ZAI_API_KEY}"; };
          };
          "web-reader" = {
            type = "remote";
            url = "https://api.z.ai/api/mcp/web_reader/mcp";
            oauth = false;
            headers = { Authorization = "Bearer {env:ZAI_API_KEY}"; };
          };
          "zread" = {
            type = "remote";
            url = "https://api.z.ai/api/mcp/zread/mcp";
            oauth = false;
            headers = { Authorization = "Bearer {env:ZAI_API_KEY}"; };
          };
          "zai-vision" = {
            type = "local";
            command = [ "npx" "-y" "@z_ai/mcp-server" ];
            environment = {
              Z_AI_API_KEY = "{env:ZAI_API_KEY}";
              Z_AI_MODE = "ZAI";
            };
            enabled = false;
          };
        };

        # Override built-in agent models to GPT 5.5
        agent = {
          build = {
            model = "openai/gpt-5.5";
          };
          plan = {
            model = "openai/gpt-5.5";
          };
        };
      };

      # TUI configuration.
      # opencode split TUI config into a separate tui.json; manage it here so
      # opencode doesn't migrate it at runtime and the oh-my-openagent/tui
      # plugin entry (required for the plugin's TUI features) is always present.
      "opencode/tui.json".text = builtins.toJSON {
        "$schema" = "https://opencode.ai/tui.json";
        plugin = [ "oh-my-openagent/tui" ];
        keybinds.app_exit = "ctrl+c,<leader>q";
      };

      # oh-my-openagent configuration
      "opencode/oh-my-openagent.json".text = builtins.toJSON {
        "$schema" = "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json";

        tmux = {
          enabled = cfg.enableTmux;
          layout = "main-vertical";
          main_pane_size = 60;
          main_pane_min_width = 120;
          agent_pane_min_width = 40;
          isolation = "inline";
        };

        disabled_mcps = [ "websearch" ];
        disabled_hooks = [ "keyword-detector" ];

        background_task = {
          defaultConcurrency = 5;
          staleTimeoutMs = 180000;
        };

        runtime_fallback = {
          enabled = true;
          retry_on_errors = [ 400 429 503 529 ];
          max_fallback_attempts = 3;
          cooldown_seconds = 60;
          notify_on_fallback = true;
        };

        git_master = {
          commit_footer = false;
          include_co_authored_by = false;
          git_env_prefix = "GIT_MASTER=1";
        };

        sisyphus_agent = {
          disabled = false;
          default_builder_enabled = true;
          planner_enabled = true;
          replace_plan = false;
        };

        team_mode = {
          enabled = true;
          tmux_visualization = cfg.enableTmux;
          max_parallel_members = 4;
          max_members = 8;
          max_messages_per_run = 10000;
          max_wall_clock_minutes = 120;
          max_member_turns = 500;
          message_payload_max_bytes = 32768;
          recipient_unread_max_bytes = 262144;
          mailbox_poll_interval_ms = 3000;
        };

        agents = {
          sisyphus = {
            model = "zai-coding-plan/glm-5.2";
            fallback_models = [ "openai/gpt-5.5" ];
          };
          "sisyphus-junior" = {
            model = "zai-coding-plan/glm-5.2";
            fallback_models = [ "openai/gpt-5.5" ];
          };
          atlas = {
            model = "zai-coding-plan/glm-5.2";
            fallback_models = [ "openai/gpt-5.5" ];
          };
          build = {
            model = "zai-coding-plan/glm-5.2";
            fallback_models = [ "openai/gpt-5.5" ];
          };
          plan = {
            model = "openai/gpt-5.5";
            variant = "xhigh";
            fallback_models = [ "zai-coding-plan/glm-5.2" ];
          };
          oracle = {
            model = "openai/gpt-5.5";
            variant = "xhigh";
            fallback_models = [ "zai-coding-plan/glm-5.2" ];
          };
          prometheus = {
            model = "openai/gpt-5.5";
            variant = "xhigh";
            fallback_models = [ "zai-coding-plan/glm-5.2" ];
          };
          metis = {
            model = "openai/gpt-5.5";
            variant = "xhigh";
            fallback_models = [ "zai-coding-plan/glm-5.2" ];
          };
          momus = {
            model = "openai/gpt-5.5";
            variant = "xhigh";
            fallback_models = [ "zai-coding-plan/glm-5.2" ];
          };
          "OpenCode-Builder" = {
            model = "zai-coding-plan/glm-5.2";
            fallback_models = [ "openai/gpt-5.5" ];
          };
          librarian = {
            model = "zai-coding-plan/glm-5.2";
            fallback_models = [ "openai/gpt-5.5" ];
          };
          explore = {
            model = "zai-coding-plan/glm-5.2";
            fallback_models = [ "openai/gpt-5.5" ];
          };
          "multimodal-looker" = {
            model = "zai-coding-plan/glm-5v-turbo";
            fallback_models = [ "zai-coding-plan/glm-5.2" ];
          };
        };

        categories = {
          visual-engineering = { model = "zai-coding-plan/glm-5.2"; fallback_models = [ "openai/gpt-5.5" ]; temperature = 0.7; };
          ultrabrain = { model = "openai/gpt-5.5"; variant = "xhigh"; fallback_models = [ "zai-coding-plan/glm-5.2" ]; temperature = 0.1; };
          deep = { model = "openai/gpt-5.5"; variant = "xhigh"; fallback_models = [ "zai-coding-plan/glm-5.2" ]; temperature = 0.2; };
          artistry = { model = "zai-coding-plan/glm-5.2"; fallback_models = [ "openai/gpt-5.5" ]; temperature = 0.9; };
          quick = { model = "zai-coding-plan/glm-5.2"; temperature = 0.3; };
          writing = { model = "zai-coding-plan/glm-5.2"; fallback_models = [ "openai/gpt-5.5" ]; temperature = 0.5; };
          unspecified-low = { model = "zai-coding-plan/glm-5.2"; temperature = 0.3; };
          unspecified-high = { model = "zai-coding-plan/glm-5.2"; fallback_models = [ "openai/gpt-5.5" ]; temperature = 0.3; };
        };
      };

      # ============================================================
      # Engineering workflow agents
      # ============================================================
      "opencode/agents/discovery.md".source = ./agents/discovery.md;
      "opencode/agents/design.md".source = ./agents/design.md;
      "opencode/agents/execute.md".source = ./agents/execute.md;
      "opencode/agents/planner.md".source = ./agents/planner.md;
      "opencode/agents/plan-reviewer.md".source = ./agents/plan-reviewer.md;
      "opencode/agents/code-reviewer.md".source = ./agents/code-reviewer.md;
      "opencode/agents/worker.md".source = ./agents/worker.md;
      "opencode/agents/ui-worker.md".source = ./agents/ui-worker.md;
      "opencode/agents/researcher.md".source = ./agents/researcher.md;

      # ============================================================
      # Engineering workflow skills
      # ============================================================

      # Adapted skills (OpenCode-specific delegation syntax)
      "opencode/skills/discovery/SKILL.md".source = ./skills/discovery/SKILL.md;
      "opencode/skills/discovery/references".source = "${repoRoot}/skills/discovery/references";
      "opencode/skills/design/SKILL.md".source = ./skills/design/SKILL.md;
      "opencode/skills/design/references".source = "${repoRoot}/skills/design/references";
      "opencode/skills/execution-orchestrator/SKILL.md".source = ./skills/execution-orchestrator/SKILL.md;

      # Shared skills (unchanged, same files used by Pi)
      "opencode/skills/research".source = "${repoRoot}/skills/research";
      "opencode/skills/create-plan".source = "${repoRoot}/skills/create-plan";
      "opencode/skills/create-worklog".source = "${repoRoot}/skills/create-worklog";
      "opencode/skills/execute-task".source = "${repoRoot}/skills/execute-task";
      "opencode/skills/review-plan".source = "${repoRoot}/skills/review-plan";
      "opencode/skills/review-code".source = "${repoRoot}/skills/review-code";
      "opencode/skills/review-approach".source = "${repoRoot}/skills/review-approach";
      "opencode/skills/review-epic".source = "${repoRoot}/skills/review-epic";
      "opencode/skills/assess-repo".source = "${repoRoot}/skills/assess-repo";
      "opencode/skills/create-skills".source = "${repoRoot}/skills/create-skills";
      "opencode/skills/create-new-repo-docs".source = "${repoRoot}/skills/create-new-repo-docs";
    };
  };
}
