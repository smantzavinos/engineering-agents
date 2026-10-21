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

Powerline is the default profile. Pi's native fullscreen layout owns the fixed input, transcript scrolling, selection, and cursor rendering inside the current terminal pane. Powerline supplies the detailed `nerd` status rows, startup welcome overlay, Catppuccin-aligned colors, forced Nerd Font glyphs for tmux sessions, and Pi's reported token-cost estimate even for subscription models. Its `powerline.config`, `powerline.shortcuts`, `powerline.nerdFonts`, and `powerline.theme` options configure the extension; transcript keys belong to Pi's `keybindings.json`. Override only the values you need:

```nix
engineering-agents.pi.powerline = {
  config = {
    preset = "full";
    queue.compactPromptMode = "native";
    cost.subscriptionDisplay = "reported-cost";
    path = {
      mode = "abbreviated";
      maxLength = 36;
    };
  };
  shortcuts = { }; # Extension actions only, e.g. stashHistory or copyEditor.
  nerdFonts = "force"; # use "auto" or "disable" when appropriate
  theme.colors = {
    model = "#cba6f7";
    path = "#94e2d5";
  };
};
```

### Native fullscreen migration

Powerline 0.20.2 replaces the old extension-owned fixed editor with Pi's native fullscreen layout. Activation selects `tuiMode = "fullscreen"` for Powerline and removes the retired `powerline.fixedEditor`, `powerline.mouseScroll`, and `powerlineShortcuts.scrollChatUp`/`scrollChatDown` keys from existing writable settings. Other runtime preferences survive the recursive merge; declarative values win. Zentui keeps its separate regular-mode compositor.

- `Ctrl+Alt+U` / `Ctrl+Alt+D` now scroll the transcript one line through `tui.altScreen.lineUp` / `lineDown`. The old extension moved ten lines per press; use native PageUp/PageDown for larger jumps.
- `PageUp` / `PageDown` scroll by a page; `Ctrl+Home` / `Ctrl+End` go to the beginning/end. `Ctrl+Shift+F` searches the transcript. Native message navigation replaces Powerline's separate user/assistant jump actions and scroll-away shortcut card; those extension features are not retained.
- Pi owns mouse selection and enables copy-on-select by default. `app.message.copy` remains unbound so `Ctrl+X` stays available to the leader-key extension. Test clipboard and link handling in the actual terminal/tmux path.
- Fullscreen uses the alternate screen, like Neovim, within the existing pane. Browse live output with Pi rather than tmux scrollback. On normal exit, Pi defaults to printing the transcript onto the normal screen; `fullscreenExitOutput = "resume-hint"` is the alternative Pi setting.
- `powerline.queue.compactPromptMode = "native"` preserves `/compact <text>` as compaction instructions. It also leaves prompts submitted during compaction in Pi's native queue rather than Powerline's post-compaction queue.
- Bash ghost completions are now opt-in (`bashMode.completions = true`). Restore stashed drafts explicitly with `Alt+S` (or `Ctrl+S` in the editor); agent completion no longer restores them automatically. Delayed send and AI-assisted follow-up routing remain off by default.

Use the sandbox before applying this migration or any profile/visual change to the active Home Manager generation. Check mid-line edits, multiline drafts, scrolling during streaming, clipboard/link handling, terminal resizing, pane switching, status placement, and compaction behavior. A successful load check does not replace this hands-on acceptance pass.

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
