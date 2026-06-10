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

  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, llmAgents }:
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
          defaultModel = "glm-5";
          defaultThinkingLevel = "medium";
          theme = "catppuccin-mocha";
        };

        # OpenCode model configuration
        opencode = {
          model = "zai-coding-plan/glm-4.7";
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
        opencode = import ./nix/modules/opencode { inherit self llmAgents; };
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
      # Packages
      # ============================================================
      packages = forAllSystems ({ system, pkgs, ... }: {
        default = self.packages.${system}.engineering-agents-docs;

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
              engineering-agents.pi.enableGitNexus = false;
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
              engineering-agents.pi.enableGitNexus = false;
              engineering-agents.pi.enableAgentKit = false;
              engineering-agents.pi.enableVisualExplainer = false;
              engineering-agents.opencode.enable = true;
            }
          ];
        };
      });
    };
}
