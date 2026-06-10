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

in
{
  options.engineering-agents.opencode = {
    enable = lib.mkEnableOption "OpenCode CLI with engineering-agents configuration";

    model = lib.mkOption {
      type = lib.types.str;
      default = "zai-coding-plan/glm-4.7";
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

        keybinds = {
          app_exit = "ctrl+c,<leader>q";
        };

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

          openai = {
            options = {
              include = [ "reasoning.encrypted_content" ];
              store = false;
            };
            models = {
              "gpt-5.2" = {
                variants = {
                  none = { reasoningEffort = "none"; reasoningSummary = "auto"; textVerbosity = "medium"; };
                  minimal = { reasoningEffort = "minimal"; reasoningSummary = "auto"; textVerbosity = "medium"; };
                  low = { reasoningEffort = "low"; reasoningSummary = "auto"; textVerbosity = "medium"; };
                  medium = { reasoningEffort = "medium"; reasoningSummary = "auto"; textVerbosity = "medium"; };
                  high = { reasoningEffort = "high"; reasoningSummary = "detailed"; textVerbosity = "medium"; };
                  xhigh = { reasoningEffort = "xhigh"; reasoningSummary = "detailed"; textVerbosity = "medium"; };
                };
              };
              "gpt-5.5" = {
                variants = {
                  none = { reasoningEffort = "none"; reasoningSummary = "auto"; textVerbosity = "medium"; };
                  minimal = { reasoningEffort = "minimal"; reasoningSummary = "auto"; textVerbosity = "medium"; };
                  low = { reasoningEffort = "low"; reasoningSummary = "auto"; textVerbosity = "medium"; };
                  medium = { reasoningEffort = "medium"; reasoningSummary = "auto"; textVerbosity = "medium"; };
                  high = { reasoningEffort = "high"; reasoningSummary = "detailed"; textVerbosity = "medium"; };
                  xhigh = { reasoningEffort = "xhigh"; reasoningSummary = "detailed"; textVerbosity = "medium"; };
                };
              };
              "gpt-5.2-codex" = {
                variants = {
                  none = { reasoningEffort = "none"; reasoningSummary = "auto"; textVerbosity = "medium"; };
                  minimal = { reasoningEffort = "minimal"; reasoningSummary = "auto"; textVerbosity = "medium"; };
                  low = { reasoningEffort = "low"; reasoningSummary = "auto"; textVerbosity = "medium"; };
                  medium = { reasoningEffort = "medium"; reasoningSummary = "auto"; textVerbosity = "medium"; };
                  high = { reasoningEffort = "high"; reasoningSummary = "detailed"; textVerbosity = "medium"; };
                  xhigh = { reasoningEffort = "xhigh"; reasoningSummary = "detailed"; textVerbosity = "medium"; };
                };
              };
            };
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
        };

        sisyphus_agent = {
          disabled = false;
          default_builder_enabled = true;
          planner_enabled = true;
          replace_plan = false;
        };

        agents = {
          sisyphus = {
            model = "zai-coding-plan/glm-5.1";
            fallback_models = [ "openai-codex/gpt-5.4" ];
          };
          "sisyphus-junior" = {
            model = "zai-coding-plan/glm-5.1";
            fallback_models = [ "openai-codex/gpt-5.4" ];
          };
          atlas = {
            model = "zai-coding-plan/glm-4.7";
            fallback_models = [ "openai/gpt-5.2" ];
          };
          build = {
            model = "openai-codex/gpt-5.4";
            variant = "xhigh";
            fallback_models = [ "zai-coding-plan/glm-5.1" ];
          };
          plan = {
            model = "openai-codex/gpt-5.5";
            variant = "xhigh";
            fallback_models = [ "zai-coding-plan/glm-5.1" ];
          };
          oracle = {
            model = "openai-codex/gpt-5.5";
            variant = "xhigh";
            fallback_models = [ "zai-coding-plan/glm-5.1" ];
          };
          prometheus = {
            model = "openai-codex/gpt-5.5";
            variant = "xhigh";
            fallback_models = [ "zai-coding-plan/glm-5.1" ];
          };
          metis = {
            model = "openai-codex/gpt-5.5";
            variant = "xhigh";
            fallback_models = [ "zai-coding-plan/glm-5.1" ];
          };
          momus = {
            model = "openai-codex/gpt-5.5";
            variant = "xhigh";
            fallback_models = [ "zai-coding-plan/glm-5.1" ];
          };
          "OpenCode-Builder" = {
            model = "openai-codex/gpt-5.4";
            variant = "xhigh";
            fallback_models = [ "zai-coding-plan/glm-5.1" ];
          };
          librarian = {
            model = "zai-coding-plan/glm-4.7";
            fallback_models = [ "openai/gpt-5.2" ];
          };
          explore = {
            model = "zai-coding-plan/glm-4.7-flash";
            fallback_models = [ "zai-coding-plan/glm-4.7" ];
          };
          "multimodal-looker" = {
            model = "zai-coding-plan/glm-4.6v";
            fallback_models = [ "zai-coding-plan/glm-4.7" ];
          };
        };

        categories = {
          visual-engineering = { model = "zai-coding-plan/glm-4.7"; temperature = 0.7; };
          ultrabrain = { model = "openai-codex/gpt-5.5"; variant = "xhigh"; temperature = 0.1; };
          deep = { model = "openai-codex/gpt-5.4"; variant = "medium"; temperature = 0.2; };
          artistry = { model = "zai-coding-plan/glm-4.7"; temperature = 0.9; };
          quick = { model = "zai-coding-plan/glm-4.7-flash"; temperature = 0.3; };
          writing = { model = "zai-coding-plan/glm-4.7"; temperature = 0.5; };
          unspecified-low = { model = "zai-coding-plan/glm-4.5-flash"; temperature = 0.3; };
          unspecified-high = { model = "zai-coding-plan/glm-4.7"; temperature = 0.3; };
        };
      };
    };
  };
}
