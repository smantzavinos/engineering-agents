# Development Environment

## Required Tooling
- `bash`, `jq`, and `node` are required for the repo-local fast suite.
- `nix` is required for flake evaluation in broader verification.
- `pi` plus a completed Home Manager apply are required for proof-set verification and CLI smoke checks.

## Setup and Apply
1. Ensure Home Manager is available in your local environment.
2. Import this flake's Home Manager module in your personal configuration.
3. Apply the repo-managed tooling with:

```bash
home-manager switch --flake .#<hostname>
```

4. Authenticate the installed tools when needed (`/login` inside `pi`, `opencode auth login` for OpenCode).

## Pi Footer Profile
The Pi module manages Powerline and Zentui sources but loads exactly one footer/editor extension. Set the profile in the Home Manager configuration and apply it; do not load both extensions in one Pi process.

```nix
engineering-agents.pi = {
  enable = true;
  footer = "powerline"; # default; use "zentui" to select Zentui instead
};
```

Powerline is the default profile. Its `powerline.config`, `powerline.shortcuts`, `powerline.nerdFonts`, and `powerline.theme` module options provide declarative visual configuration. The defaults use the detailed `nerd` preset, fixed editor, startup welcome overlay, Catppuccin-aligned colors, `Ctrl+Alt+U`/`Ctrl+Alt+D` fixed-editor scrolling, forced Nerd Font glyphs for tmux sessions, and Pi's reported token-cost estimate even for subscription models. Override only the values you need:

```nix
engineering-agents.pi.powerline = {
  config = {
    preset = "full";
    fixedEditor = true;
    mouseScroll = true;
    cost.subscriptionDisplay = "reported-cost";
    path = {
      mode = "abbreviated";
      maxLength = 36;
    };
  };
  shortcuts = {
    scrollChatUp = "ctrl+alt+u";
    scrollChatDown = "ctrl+alt+d";
  };
  nerdFonts = "force"; # use "auto" or "disable" when appropriate
  theme.colors = {
    model = "#cba6f7";
    path = "#94e2d5";
  };
};
```

Use the sandbox before applying a profile or visual change to the active Home Manager generation.

## Repo-local Pi Development Sandbox
Use the sandbox to test the current checkout's Pi module, including uncommitted changes, without pushing or switching the active Home Manager generation:

```bash
# Build/activate into .pi-dev/ and launch Pi.
./scripts/pi-dev.sh

# Copy the current Pi credentials into the sandbox, then launch.
./scripts/pi-dev.sh --copy-auth

# Build/activate and run the live proof-set against the sandbox.
./scripts/pi-dev.sh --verify

# Remove sandbox packages, sessions, generated configuration, and copied credentials.
./scripts/pi-dev.sh --reset
```

The sandbox sets repo-local `HOME`, `XDG_STATE_HOME`, and `XDG_CACHE_HOME` under `.pi-dev/`; it does not modify `~/.pi` or the active Home Manager generation. `--copy-auth` copies `~/.pi/agent/auth.json` with private permissions and never symlinks or writes to that source file. The first activation requires `nix` and network access to materialize managed packages. Later activations reuse unchanged pinned package installations.

## Verification Entry Points
- `./tests/run-tests.sh fast` — repo-local shell specs; use as the task completion gate.
- `./tests/run-tests.sh all` — repo-local specs plus flake evaluation and Pi proof-set verification; use before plan completion.
- `./tests/run-tests.sh full` — everything in `all` plus Pi CLI smoke checks.
- `bash tests/specs/repo-readiness-docs-spec.sh` — targeted fast feedback for the readiness-doc contract introduced by this plan.

For the canonical testing-level mapping and gate roles, see `docs/testing-strategy.md`. For suite inventory and individual spec entry points, see `tests/README.md`.
