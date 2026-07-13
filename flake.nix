{
  description = "Engineering Agents — Autonomous coding agent process, skills, agents, and Nix-managed Pi/OpenCode installation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pi (pi-mono) coding agent
    llmAgents = {
      url = "github:numtide/llm-agents.nix";
    };

    # Visual Explainer skill (external, non-flake source)
    visualExplainer = {
      url = "github:nicobailon/visual-explainer";
      flake = false;
    };

  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, llmAgents, visualExplainer }:
    let
      # System types to support
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      forAllSystems = fn: nixpkgs.lib.genAttrs supportedSystems (system: fn {
        inherit system;
        pkgs = nixpkgs.legacyPackages.${system};
        pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
      });

      # Default Pi/OpenCode configuration options
      defaultConfig = {
        # Pi model configuration
        pi = {
          defaultProvider = "zai-coding-plan";
          defaultModel = "glm-5.2";
          defaultThinkingLevel = "medium";
          theme = "catppuccin-mocha";
        };

        # OpenCode model configuration
        opencode = {
          model = "openai/gpt-5.5";
        };
      };
    in
    {
      # ============================================================
      # Home Manager Modules
      # ============================================================
      # Import these in your home-manager config:
      #   imports = [ engineering-agents.homeManagerModules.pi engineering-agents.homeManagerModules.opencode ];
      #
      # Or use the unified module:
      #   imports = [ engineering-agents.homeManagerModules.default ];
      # ============================================================
      homeManagerModules = {
        # Unified module that imports both Pi and OpenCode
        default = { config, lib, pkgs, ... }: {
          imports = [
            self.homeManagerModules.pi
            self.homeManagerModules.opencode
          ];
        };

        # Pi coding agent module
        pi = import ./nix/modules/pi { inherit self llmAgents; };

        # OpenCode CLI module
        opencode = import ./nix/modules/opencode { inherit self llmAgents visualExplainer; };
      };

      # ============================================================
      # NixOS Modules (for system service users without Home Manager)
      # ============================================================
      nixosModules = {
        # OpenCode config delivery for system users via activation script
        opencode-for-user = import ./nix/modules/opencode/nixos-user.nix { inherit self llmAgents visualExplainer; };
      };

      # ============================================================
      # Overlays
      # ============================================================
      overlays.default = final: prev: {
        engineering-agents-scripts = final.runCommand "engineering-agents-scripts" { } ''
          mkdir -p $out/bin
          cp ${./scripts/check-updates.sh} $out/bin/check-updates
          cp ${./scripts/pi-launch-wrapper.sh} $out/bin/pi-launch-wrapper
          chmod +x $out/bin/check-updates $out/bin/pi-launch-wrapper
        '';
      };

      # ============================================================
      # Library functions (for external consumers to build custom configs)
      # ============================================================
      lib = forAllSystems ({ system, pkgs, ... }: {
        inherit (import ./nix/modules/opencode/config.nix {
          lib = pkgs.lib;
          inherit pkgs self;
        }) makeOpenCodeConfig;
      });

      # ============================================================
      # Packages
      # ============================================================
      packages = forAllSystems ({ system, pkgs, ... }: {
        default = self.packages.${system}.engineering-agents-docs;

        # Pre-built default OpenCode config derivation for inspection/testing.
        # See nix/modules/opencode/config.nix for the makeOpenCodeConfig function.
        opencode-config-default = (import ./nix/modules/opencode/config.nix {
          lib = pkgs.lib;
          inherit pkgs self;
        }).makeOpenCodeConfig {};

        # Documentation bundle
        engineering-agents-docs = pkgs.runCommand "engineering-agents-docs" { } ''
          mkdir -p $out/share/doc/engineering-agents
          cp -r ${./docs} $out/share/doc/engineering-agents/docs
          cp -r ${./skills} $out/share/doc/engineering-agents/skills
          cp -r ${./agents} $out/share/doc/engineering-agents/agents
          cp ${./README.md} $out/share/doc/engineering-agents/README.md
        '';

        check-updates = pkgs.writeShellScriptBin "check-updates" ''
          export PI_UPDATE_CHECKER_HELPER="''${PI_UPDATE_CHECKER_HELPER:-${self}/nix/modules/pi/check-managed-package-status.mjs}"
          export PI_UPDATE_CHECKER_NODE_BIN="''${PI_UPDATE_CHECKER_NODE_BIN:-${pkgs.nodejs}/bin/node}"
          export PI_UPDATE_CHECKER_NPM_BIN="''${PI_UPDATE_CHECKER_NPM_BIN:-${pkgs.nodejs}/bin/npm}"
          export PI_UPDATE_CHECKER_GIT_BIN="''${PI_UPDATE_CHECKER_GIT_BIN:-${pkgs.git}/bin/git}"
          export PI_UPDATE_CHECKER_PYTHON_BIN="''${PI_UPDATE_CHECKER_PYTHON_BIN:-${pkgs.python3}/bin/python3}"
          exec ${self}/scripts/check-updates.sh "$@"
        '';

        pi-launch-wrapper = pkgs.writeShellScriptBin "pi" ''
          export PI_WRAPPER_REAL_PI_BIN="${llmAgents.packages.${system}.pi}/bin/pi"
          export PI_WRAPPER_NODE_BIN="${pkgs.nodejs}/bin/node"
          export PI_WRAPPER_STATUS_HELPER="${self}/nix/modules/pi/check-managed-package-status.mjs"
          export PI_WRAPPER_NPM_BIN="${pkgs.nodejs}/bin/npm"
          export PI_WRAPPER_GIT_BIN="${pkgs.git}/bin/git"
          exec ${self}/scripts/pi-launch-wrapper.sh "$@"
        '';
      });

      # ============================================================
      # Dev Shell
      # ============================================================
      devShells = forAllSystems ({ system, pkgs, ... }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            nodejs
            jq
            git
          ];
        };
      });

      # ============================================================
      # Templates
      # ============================================================
      templates = {
        default = {
          path = ./templates/default;
          description = "Starter configuration for using engineering-agents with Pi";
        };
      };

      # ============================================================
      # Checks — build-without-apply module instantiation tests
      # ============================================================
      # `nix flake check` builds these. They prove the modules can be
      # imported and instantiated by home-manager without errors, and
      # that the expected files appear in the activation package.
      # ============================================================
      checks = forAllSystems ({ system, pkgs, ... }: let
        testUser = "testuser";
        testHome = "/home/${testUser}";
      in {
        # OpenCode config derivation produces the expected file tree
        opencode-config-shape = pkgs.runCommand "opencode-config-shape-check" {} ''
          cfgd=${self.packages.${system}.opencode-config-default}
          test -f "$cfgd/opencode/opencode.json" || { echo "MISSING: opencode.json"; exit 1; }
          test -f "$cfgd/opencode/oh-my-openagent.json" || { echo "MISSING: oh-my-openagent.json"; exit 1; }
          test -f "$cfgd/opencode/tui.json" || { echo "MISSING: tui.json"; exit 1; }
          test -f "$cfgd/opencode/agents/discovery.md" || { echo "MISSING: agents/discovery.md"; exit 1; }
          test -f "$cfgd/opencode/agents/design.md" || { echo "MISSING: agents/design.md"; exit 1; }
          test -f "$cfgd/opencode/agents/execute.md" || { echo "MISSING: agents/execute.md"; exit 1; }
          test -d "$cfgd/opencode/skills/discovery" || { echo "MISSING: skills/discovery"; exit 1; }
          test -d "$cfgd/opencode/skills/design" || { echo "MISSING: skills/design"; exit 1; }
          test -d "$cfgd/opencode/skills/execution-orchestrator" || { echo "MISSING: skills/execution-orchestrator"; exit 1; }
          test -d "$cfgd/opencode/skills/research" || { echo "MISSING: skills/research"; exit 1; }
          test -d "$cfgd/opencode/skills/create-plan" || { echo "MISSING: skills/create-plan"; exit 1; }
          test -d "$cfgd/opencode/skills/execute-task" || { echo "MISSING: skills/execute-task"; exit 1; }
          touch $out
        '';

        # Parameterization: zai-only strips google/openai providers, minimal strips plugins
        opencode-config-parameterization = pkgs.runCommand "opencode-config-parameterization-check" {} ''
          zaiOnly=${self.lib.${system}.makeOpenCodeConfig { providers = "zai-only"; }}
          minimal=${self.lib.${system}.makeOpenCodeConfig { plugins = "minimal"; }}

          # zai-only: opencode.json must NOT have google or openai provider keys
          if ${pkgs.jq}/bin/jq -e '.provider | has("google")' "$zaiOnly/opencode/opencode.json" >/dev/null 2>&1; then
            echo "FAIL: zai-only config still has google provider"; exit 1
          fi
          if ${pkgs.jq}/bin/jq -e '.provider | has("openai")' "$zaiOnly/opencode/opencode.json" >/dev/null 2>&1; then
            echo "FAIL: zai-only config still has openai provider"; exit 1
          fi

          # minimal: opencode.json plugin list must have exactly 1 entry (oh-my-openagent)
          pluginCount=$(${pkgs.jq}/bin/jq '.plugin | length' "$minimal/opencode/opencode.json")
          if [ "$pluginCount" != "1" ]; then
            echo "FAIL: minimal plugins should have 1 entry, got $pluginCount"; exit 1
          fi

          touch $out
        '';

        # NixOS opencode-for-user module instantiates and emits the activation
        # script that materializes the config into targetDir.
        opencode-for-user-module =
          let
            mockBaseModule = { config, lib, ... }: {
              options.system.activationScripts = lib.mkOption {
                type = lib.types.attrsOf (lib.types.submodule {
                  options.text = lib.mkOption { type = lib.types.str; default = ""; };
                  options.deps = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
                });
                default = {};
              };
            };
            eval = nixpkgs.lib.evalModules {
              modules = [
                mockBaseModule
                self.nixosModules.opencode-for-user
                {
                  _module.args.pkgs = pkgs;
                  engineering-agents.opencode-for-user = {
                    enable = true;
                    user = "testuser";
                    group = "testgroup";
                    targetDir = "/tmp/test-opencode";
                    args = {};
                  };
                }
              ];
            };
            scriptText = eval.config.system.activationScripts."opencode-for-user".text;
          in
          pkgs.runCommand "opencode-for-user-module-check" {
            inherit scriptText;
          } ''
            # The script uses a shell `$target` var, so assert on invariants
            # that actually appear in the text, not expanded paths.
            echo "$scriptText" | grep -q 'ln -sfn' || {
              echo "FAIL: activation script must use ln -sfn to materialize config"
              echo "Script: $scriptText"
              exit 1
            }
            echo "$scriptText" | grep -q 'target="/tmp/test-opencode/opencode"' || {
              echo "FAIL: activation script must target the configured targetDir/opencode"
              echo "Script: $scriptText"
              exit 1
            }
            echo "$scriptText" | grep -q '/opencode.json' || {
              echo "FAIL: activation script must symlink opencode.json"
              echo "Script: $scriptText"
              exit 1
            }
            echo "$scriptText" | grep -q '/agents' || {
              echo "FAIL: activation script must symlink the agents directory"
              echo "Script: $scriptText"
              exit 1
            }
            touch $out
          '';

        # Co-evolution guard: scan agent markdown for plugin references and
        # assert any referenced plugin is in the default plugin set. Prevents
        # a future agent from silently depending on a plugin that consumers
        # using plugins = "minimal" (e.g., hermes) don't have.
        opencode-agent-plugin-deps = pkgs.runCommand "opencode-agent-plugin-deps-check" {} ''
          # Plugin names we manage (without @version suffix)
          knownPlugins="oh-my-openagent opencode-openai-codex-auth opencode-ignore opencode-direnv opencode-md-table-formatter"

          # Grep agent markdown for plugin-like references (@scope/name or name@version patterns)
          # and extract unique plugin names found
          found=$(${pkgs.gnugrep}/bin/grep -rohE '(@[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+|[a-zA-Z0-9_-]+)@[0-9]' ${./nix/modules/opencode/agents}/ 2>/dev/null | sed 's/@[0-9].*//' | sort -u || true)

          if [ -z "$found" ]; then
            # No plugin references found in agent files — baseline passes
            touch $out
            exit 0
          fi

          # Check each found plugin against known list
          for plugin in $found; do
            # Strip @scope/ prefix for comparison
            baseName=$(echo "$plugin" | sed 's/^@[^/]*\///')
            if ! echo "$knownPlugins" | grep -qw "$baseName"; then
              echo "FAIL: agent file references plugin '$plugin' which is not in the managed plugin set"
              echo "Managed plugins: $knownPlugins"
              echo "If this plugin is needed, add it to defaultPlugins in nix/modules/opencode/config.nix"
              exit 1
            fi
          done

          touch $out
        '';

        # Pi module builds a valid activation package
        pi-module = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            self.homeManagerModules.pi
            {
              home.username = testUser;
              home.homeDirectory = testHome;
              home.stateVersion = "25.05";
              engineering-agents.pi.enable = true;
              engineering-agents.pi.enableAgentKit = false;
              engineering-agents.pi.enableVisualExplainer = false;
            }
          ];
        };

        # OpenCode module builds a valid activation package
        opencode-module = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            self.homeManagerModules.opencode
            {
              home.username = testUser;
              home.homeDirectory = testHome;
              home.stateVersion = "25.05";
              engineering-agents.opencode.enable = true;
            }
          ];
        };

        # Both modules together
        both-modules = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            self.homeManagerModules.default
            {
              home.username = testUser;
              home.homeDirectory = testHome;
              home.stateVersion = "25.05";
              engineering-agents.pi.enable = true;
              engineering-agents.pi.enableAgentKit = false;
              engineering-agents.pi.enableVisualExplainer = false;
              engineering-agents.opencode.enable = true;
            }
          ];
        };
      });
    };
}
