# Claude Code CLI Home Manager module
#
# Installs the Claude Code CLI from the llm-agents.nix flake input.
#
# Usage in your home-manager config:
#   imports = [ engineering-agents.homeManagerModules.claude-code ];
#   engineering-agents.claude-code.enable = true;
#
{ self, llmAgents }:

{ config, lib, pkgs, ... }:

let
  cfg = config.engineering-agents.claude-code;
  claudeCodePkg = llmAgents.packages.${pkgs.system}.claude-code;
in
{
  options.engineering-agents.claude-code = {
    enable = lib.mkEnableOption "Claude Code CLI from llm-agents.nix";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ claudeCodePkg ];
  };
}
