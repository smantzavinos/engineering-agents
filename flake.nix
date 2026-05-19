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

    # OpenCode CLI
    opencode = {
      url = "github:sst/opencode/v1.2.10";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, llmAgents, opencode }:
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
        opencode = import ./nix/modules/opencode { inherit self opencode; };
      };

      # ============================================================
      # Overlays
      # ============================================================
      overlays.default = final: prev: {
        engineering-agents-scripts = final.runCommand "engineering-agents-scripts" { } ''
          mkdir -p $out/bin
          cp ${./scripts/check-updates.sh} $out/bin/check-updates
          chmod +x $out/bin/check-updates
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
    };
}
