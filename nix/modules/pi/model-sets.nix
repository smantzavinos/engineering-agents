# One model table for session defaults, installed roles and terminal presets.
{ lib }:
{ modelSet ? "direct", zaiEnabled ? true }:
let
  role = model: thinking: { inherit model thinking; };
  codex = role "openai-codex/gpt-5.6-sol";
  copilot = model: role "github-copilot/${model}";
  flash = role (if zaiEnabled then "zai-coding-plan/glm-5.3-flash" else "openai-codex/gpt-5.6-luna");

  sets = {
    direct = {
      default = codex "medium";
      plan-author = codex "high";
      implementer = codex "medium";
      reviewer = if zaiEnabled then role "zai-coding-plan/glm-5.3" "high" else codex "high";
      helper = flash "low";
      oracle = codex "xhigh";
      researcher = flash "low";
    };
    copilot = {
      default = copilot "claude-sonnet-5.5" "medium";
      plan-author = copilot "claude-opus-5.5" "high";
      implementer = copilot "gpt-6.2-sol" "medium";
      reviewer = copilot "claude-opus-5.5" "high";
      helper = copilot "claude-haiku-5.5" "low";
      oracle = copilot "claude-fable-5.2" "high";
      researcher = copilot "claude-sonnet-5.5" "low";
    };
  };
  selected = sets.${modelSet};
  inherit (selected) plan-author implementer reviewer helper;
  default = lib.splitString "/" selected.default.model;
  preset = lib.splitString "/" plan-author.model;
in
{
  defaultProvider = lib.head default;
  defaultModel = lib.last default;
  presetProvider = lib.head preset;
  presetModel = lib.last preset;
  defaultThinkingLevel = selected.default.thinking;
  enabledModels = if modelSet == "copilot" then [ "github-copilot/*" ] else [
    "openai-codex/gpt-5.6-luna"
    "openai-codex/gpt-5.6-terra"
    "openai-codex/gpt-5.6-sol"
  ] ++ lib.optionals zaiEnabled [
    "zai-coding-plan/glm-5.2"
    "zai-coding-plan/glm-5.3"
    "zai-coding-plan/glm-5.3-flash"
    "zai-coding-plan/glm-5.4"
  ];
  agentOverrides = (removeAttrs selected [ "default" ]) // {
    planner = plan-author;
    plan-reviewer = reviewer;
    code-reviewer = reviewer;
    worker = implementer;
    worker-high = implementer;
    ui-worker = implementer;
    worker-low = helper;
    vision = plan-author // { thinking = "medium"; };
  };
}
