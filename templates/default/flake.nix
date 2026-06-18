# Example: Using engineering-agents in your own flake
#
# 1. Add this as an input to your flake.nix
# 2. Import the modules in your home-manager config
# 3. Run: home-manager switch --flake .#<hostname>
#
{
  description = "My NixOS configuration with engineering-agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    engineering-agents = {
      url = "github:<your-username>/engineering-agents";
      # For local development:
      # url = "path:/home/you/code/engineering-agents";
    };
  };

  outputs = { self, nixpkgs, home-manager, engineering-agents, ... }:
    let
      system = "x86_64-linux";
      hostname = "myhost";
    in {
      homeConfigurations.${hostname} = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};

        modules = [
          # Import engineering-agents modules
          engineering-agents.homeManagerModules.default

          {
            home.username = "you";
            home.homeDirectory = "/home/you";
            home.stateVersion = "25.05";

            # Enable Pi with all skills, agents, and presets
            engineering-agents.pi = {
              enable = true;
              defaultModel = "glm-5.2";
              # Override models list if desired:
              # enabledModels = [ "zai-coding-plan/glm-5.2" "openai-codex/gpt-5.4" ];
            };

            # Enable OpenCode with engineering-agents configuration
            engineering-agents.opencode = {
              enable = true;
              model = "zai-coding-plan/glm-5.2";
            };
          }
        ];
      };
    };
}
