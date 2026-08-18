# nix/modules/pi/config.nix — Pure config-building functions for Pi
#
# Produces store-path derivations containing Pi agent trees, with managed
# packages materialized at BUILD time (no npm at activation):
#
#   makePiManagedPackages {}   # vendor tree + compiled facades + install-state
#   makePiConfig {}            # static agent tree (settings, models, skills, ...)
#
# Managed packages come from two offline sources:
#   - npm packages: ./managed-packages/{package.json,package-lock.json} via
#     npmConfigHook + `npm ci` from the fixed-output npm cache
#   - git packages: pinned fetchzip tarballs (40-hex commits, hashes below)
#
# The declarations fed to compile-managed-packages.mjs resolve
# `materializedPath` relative to the declarations file, so the compiled
# facades (`agent/packages/<id>`) reach their sources
# (`vendor/node_modules/<name>`) through relative symlinks that stay valid
# inside this one store path. Consumers (Home Manager shim in default.nix,
# NixOS shim in nixos-user.nix) symlink facade entries into a writable agent
# directory; nothing npm-shaped runs at activation time.
#
# Layout of the makePiManagedPackages output:
#   $out/agent/packages/<id>/            generated local facades (meta/, _source)
#   $out/agent/sources/src-<hash>        per-provenance source roots
#   $out/agent/managed-packages.*.json   declarations / report / install-state
#   $out/vendor/node_modules/            complete materialized npm tree
#   $out/declarations.json               compiler input (paths relative to $out)
#
# Consumed by:
#   - nix/modules/pi/default.nix (Home Manager shim)
#   - nix/modules/pi/nixos-user.nix (NixOS shim for system users, e.g. hermes)
#
{ lib, pkgs, self }:

let
  nodejs = pkgs.nodejs;

  # ============================================================
  # Managed Pi package declarations (single source of truth)
  # ============================================================
  # `spec` is the human-facing pin; `installSpec` must match it (the
  # install-state helper and materialized keys hash this pair). For git
  # sources the commit must also be immutable (40-hex) and match the
  # matching `gitSources` entry below — nix/AGENTS.md enforces this.
  managedPackages = {
    pi-subagents = {
      source = {
        type = "git";
        packageName = "pi-subagents";
        # v0.50.0 — required for `workflowScript` code-mode orchestration.
        # Note: the pi manifest entrypoint moved to ./index.ts in this release.
        spec = "github:nicobailon/pi-subagents#c091da1d9b660c1940ef5dc78cfeeace1aecd435";
        installSpec = "github:nicobailon/pi-subagents#c091da1d9b660c1940ef5dc78cfeeace1aecd435";
      };
    };

    pi-hooks = {
      source = {
        type = "git";
        packageName = "pi-hooks";
        spec = "github:smantzavinos/pi-hooks#1c3ed591b393793cd025ff43fa61e16828872931";
        installSpec = "github:smantzavinos/pi-hooks#1c3ed591b393793cd025ff43fa61e16828872931";
      };
    };

    pi-messenger = {
      source = {
        type = "npm";
        packageName = "pi-messenger";
        spec = "pi-messenger@0.15.0";
        installSpec = "pi-messenger@0.15.0";
        version = "0.15.0";
      };
      expose = {
        extensions = [ "./index.ts" ];
        skills = [ "pi-messenger-crew" ];
        prompts = [ ];
        themes = [ ];
      };
    };

    pi-agent-guidance = {
      source = {
        type = "npm";
        packageName = "@tmustier/pi-agent-guidance";
        spec = "@tmustier/pi-agent-guidance@0.1.5";
        installSpec = "@tmustier/pi-agent-guidance@0.1.5";
        version = "0.1.5";
      };
    };

    pi-mcp-adapter = {
      source = {
        type = "npm";
        packageName = "pi-mcp-adapter";
        spec = "pi-mcp-adapter@2.11.0";
        installSpec = "pi-mcp-adapter@2.11.0";
        version = "2.11.0";
      };
    };

    pi-web-access = {
      source = {
        type = "npm";
        packageName = "pi-web-access";
        spec = "pi-web-access@0.13.0";
        installSpec = "pi-web-access@0.13.0";
        version = "0.13.0";
      };
    };

    pi-powerline-footer = {
      source = {
        type = "git";
        packageName = "pi-powerline-footer";
        # v0.7.0 supports Pi >=0.74.0 <0.81.0, including this flake's Pi 0.80.7 pin.
        spec = "github:nicobailon/pi-powerline-footer#760f828b19349f7158409bf9f84259d9221c1784";
        installSpec = "github:nicobailon/pi-powerline-footer#760f828b19349f7158409bf9f84259d9221c1784";
      };
    };

    pi-zentui = {
      source = {
        type = "git";
        packageName = "pi-zentui";
        spec = "github:lmilojevicc/pi-zentui#d22f4f302f19682a7adc8d6cedd55e1f0d38149a";
        installSpec = "github:lmilojevicc/pi-zentui#d22f4f302f19682a7adc8d6cedd55e1f0d38149a";
      };
    };

    pi-interactive-shell = {
      source = {
        type = "npm";
        packageName = "pi-interactive-shell";
        spec = "pi-interactive-shell@0.13.0";
        installSpec = "pi-interactive-shell@0.13.0";
        version = "0.13.0";
      };
    };

    pi-subdir-context = {
      source = {
        type = "npm";
        packageName = "pi-subdir-context";
        spec = "pi-subdir-context@1.1.7";
        installSpec = "pi-subdir-context@1.1.7";
        version = "1.1.7";
      };
    };

    pi-ding = {
      source = {
        type = "npm";
        packageName = "pi-ding";
        spec = "pi-ding@0.2.2";
        installSpec = "pi-ding@0.2.2";
        version = "0.2.2";
      };
    };

    pi-notify = {
      source = {
        type = "npm";
        packageName = "pi-notify";
        spec = "pi-notify@1.4.0";
        installSpec = "pi-notify@1.4.0";
        version = "1.4.0";
      };
    };

    pi-auto-rename = {
      source = {
        type = "npm";
        packageName = "@byteowlz/pi-auto-rename";
        spec = "@byteowlz/pi-auto-rename@1.0.7";
        installSpec = "@byteowlz/pi-auto-rename@1.0.7";
        version = "1.0.7";
      };
    };

    pi-ext-leader-key = {
      source = {
        type = "git";
        packageName = "pi-ext";
        spec = "github:tomsej/pi-ext#d162f4c47ae82d2cdb5d1d499136601ff8718303";
        installSpec = "github:tomsej/pi-ext#d162f4c47ae82d2cdb5d1d499136601ff8718303";
      };
      expose = {
        extensions = [ "./extensions/leader-key/index.ts" ];
        skills = [ ];
        prompts = [ ];
        themes = [ ];
      };
    };

    pi-ext-review = {
      source = {
        type = "git";
        packageName = "pi-ext";
        spec = "github:tomsej/pi-ext#d162f4c47ae82d2cdb5d1d499136601ff8718303";
        installSpec = "github:tomsej/pi-ext#d162f4c47ae82d2cdb5d1d499136601ff8718303";
      };
      expose = {
        extensions = [ "./extensions/review/review.ts" ];
        skills = [ ];
        prompts = [ ];
        themes = [ ];
      };
    };

    pi-guardrails = {
      source = {
        type = "npm";
        packageName = "@aliou/pi-guardrails";
        spec = "@aliou/pi-guardrails@0.9.5";
        installSpec = "@aliou/pi-guardrails@0.9.5";
        version = "0.9.5";
      };
    };

    pi-preset = {
      source = {
        type = "npm";
        packageName = "@richardgill/pi-preset";
        spec = "@richardgill/pi-preset@0.0.8";
        installSpec = "@richardgill/pi-preset@0.0.8";
        version = "0.0.8";
      };
    };

    pi-prompt-template-model = {
      source = {
        type = "npm";
        packageName = "pi-prompt-template-model";
        spec = "pi-prompt-template-model@0.10.0";
        installSpec = "pi-prompt-template-model@0.10.0";
        version = "0.10.0";
      };
    };

    pi-btw = {
      source = {
        type = "npm";
        packageName = "pi-btw";
        spec = "pi-btw@0.4.1";
        installSpec = "pi-btw@0.4.1";
        version = "0.4.1";
      };
    };

    pi-gitnexus = {
      source = {
        type = "git";
        packageName = "pi-gitnexus";
        spec = "github:smantzavinos/pi-gitnexus#fa63bd3f6156cec943e42411ec0fc1909181dd2c";
        installSpec = "github:smantzavinos/pi-gitnexus#fa63bd3f6156cec943e42411ec0fc1909181dd2c";
      };
    };
  };

  # Git package pins: one immutable tarball per source repo (shared by the
  # two pi-ext packageIds). Hashes are unpacked-codeload SRI values.
  gitSources = {
    "pi-subagents" = {
      rev = "c091da1d9b660c1940ef5dc78cfeeace1aecd435";
      tarball = pkgs.fetchzip {
        url = "https://github.com/nicobailon/pi-subagents/archive/c091da1d9b660c1940ef5dc78cfeeace1aecd435.tar.gz";
        hash = "sha256-2lv3e6s+AVXL5Da/+PhSzG4b5Hc62+2MY0mjqSPBoVo=";
        stripRoot = true;
      };
    };
    "pi-hooks" = {
      rev = "1c3ed591b393793cd025ff43fa61e16828872931";
      tarball = pkgs.fetchzip {
        url = "https://github.com/smantzavinos/pi-hooks/archive/1c3ed591b393793cd025ff43fa61e16828872931.tar.gz";
        hash = "sha256-CHpl/so5oJos4croXT1d5bjKU5ODM27upXPWZx3yGq4=";
        stripRoot = true;
      };
    };
    "pi-ext" = {
      rev = "d162f4c47ae82d2cdb5d1d499136601ff8718303";
      tarball = pkgs.fetchzip {
        url = "https://github.com/tomsej/pi-ext/archive/d162f4c47ae82d2cdb5d1d499136601ff8718303.tar.gz";
        hash = "sha256-Hn21nLDHfMmmR7/9zd3E4FEt/OdqLLq5oM5SOvAecXs=";
        stripRoot = true;
      };
    };
    "pi-powerline-footer" = {
      rev = "760f828b19349f7158409bf9f84259d9221c1784";
      tarball = pkgs.fetchzip {
        url = "https://github.com/nicobailon/pi-powerline-footer/archive/760f828b19349f7158409bf9f84259d9221c1784.tar.gz";
        hash = "sha256-PMvI4EbvOjahrNuW6GAJJfzTzV5HNIER7BKKOmYMr4s=";
        stripRoot = true;
      };
    };
    "pi-zentui" = {
      rev = "d22f4f302f19682a7adc8d6cedd55e1f0d38149a";
      tarball = pkgs.fetchzip {
        url = "https://github.com/lmilojevicc/pi-zentui/archive/d22f4f302f19682a7adc8d6cedd55e1f0d38149a.tar.gz";
        hash = "sha256-H9AiPb5ed8CkiUPUCfBuE/wgWkVgGcS/w5Koyrts6zw=";
        stripRoot = true;
      };
    };
    "pi-gitnexus" = {
      rev = "fa63bd3f6156cec943e42411ec0fc1909181dd2c";
      tarball = pkgs.fetchzip {
        url = "https://github.com/smantzavinos/pi-gitnexus/archive/fa63bd3f6156cec943e42411ec0fc1909181dd2c.tar.gz";
        hash = "sha256-dWWYl09ysuiGj2IQCg+IpK056jg/EC2FD+VFvEhfX8I=";
        stripRoot = true;
      };
    };
  };

  # ============================================================
  # Default configuration values
  # ============================================================
  defaultEnabledModels = [
    "openai-codex/gpt-5.6-luna"
    "openai-codex/gpt-5.6-terra"
    "openai-codex/gpt-5.6-sol"
    "zai-coding-plan/glm-5.2"
    "zai-coding-plan/glm-5.3"
    "xai/grok-4.5"
    "xai/grok-4.6"
    "fireworks/accounts/fireworks/models/deepseek-v4-flash-0731"
    "fireworks/accounts/fireworks/models/deepseek-v4-pro-0813"
    "fireworks/accounts/fireworks/models/qwen3p7-plus"
    "fireworks/accounts/fireworks/models/qwen3p8-max"
    "fireworks/accounts/fireworks/models/kimi-k2p7-code"
    "fireworks/accounts/fireworks/models/kimi-k3"
    "fireworks/accounts/fireworks/models/minimax-m3"
    "fireworks/accounts/fireworks/models/glm-5p2"
    "fireworks/accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b"
    "fireworks/accounts/fireworks/models/muse-glimmer-30b"
  ];

  footerPackageIds = [ "pi-powerline-footer" "pi-zentui" ];

  defaultPowerlineConfig = {
    preset = "nerd";
    fixedEditor = true;
    mouseScroll = true;
    placement = "above";
    welcome = true;
    cost.subscriptionDisplay = "reported-cost";
    path = {
      mode = "abbreviated";
      maxLength = 36;
    };
  };

  defaultPowerlineShortcuts = {
    scrollChatUp = "ctrl+alt+u";
    scrollChatDown = "ctrl+alt+d";
  };

  defaultPowerlineTheme = {
    colors = {
      model = "#cba6f7";
      shellMode = "success";
      path = "#94e2d5";
      gitClean = "success";
      gitDirty = "warning";
      thinking = "thinkingOff";
      thinkingMinimal = "thinkingMinimal";
      thinkingLow = "thinkingLow";
      thinkingMedium = "thinkingMedium";
      context = "dim";
      contextWarn = "warning";
      contextError = "error";
      cost = "text";
      tokens = "muted";
      separator = "dim";
      border = "borderMuted";
    };
    icons = { };
  };

  # ============================================================
  # Managed package vendor + facade build
  # ============================================================
  piVendor = pkgs.stdenv.mkDerivation {
    pname = "pi-managed-vendor";
    version = "0.1.0";

    src = ./managed-packages;

    # Fixed-output npm cache for `npm ci` (built by fetchNpmDeps from the
    # committed lock; regenerate the hash with
    # `nix build nixpkgs#prefetch-npm-deps` after lockfile edits).
    npmDeps = pkgs.fetchNpmDeps {
      src = ./managed-packages;
      hash = "sha256-tecgw8PUTn0QApeBn8kJfuTy+6Jd5VJlZeiQ9dNIRN0=";
    };

    nativeBuildInputs = [ nodejs pkgs.npmHooks.npmConfigHook ];

    # The committed lock is generated with --install-strategy=nested (see
    # refresh-lock.sh): pi's extension loader resolves imports against the
    # literal (non-symlink-resolved) path, so every managed package must be
    # self-contained — its dependencies nested under its own directory, like
    # npm's global-install layout. The build post-process below symlinks any
    # dependency npm left at the vendor root back into the package.
    buildPhase = ''
      runHook preBuild
      export HOME="$NIX_BUILD_TOP/home"
      mkdir -p "$HOME"
      export npm_config_offline=true
      npm ci --install-strategy=nested --ignore-scripts --no-audit --no-fund
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r node_modules "$out/node_modules"
      runHook postInstall
    '';
  };

  # Pi's extension loader resolves imports against the literal (non-
  # symlink-resolved) path, so each managed package must carry its own
  # dependencies. npm's nested install covers most of them; anything npm
  # left at the vendor root (root-level direct deps, peers) is linked back
  # into the package with relative symlinks. Targets are themselves
  # self-contained, so resolution stops inside the vendor tree.
  # Pi-injected core packages are excluded: the loader provides them.
  ensureSelfContainedScript = pkgs.writeText "ensure-self-contained.mjs" ''
    import fs from 'node:fs';
    import path from 'node:path';

    const vendorRoot = process.argv[2];
    const injected = new Set([
      '@earendil-works/pi-ai',
      '@earendil-works/pi-agent-core',
      '@earendil-works/pi-coding-agent',
      '@earendil-works/pi-tui',
      '@mariozechner/pi-ai',
      '@mariozechner/pi-agent-core',
      '@mariozechner/pi-coding-agent',
      '@mariozechner/pi-tui',
      'typebox',
    ]);

    let links = 0;
    const linkInto = (packageDir, depName) => {
      const source = path.join(vendorRoot, depName);
      if (!fs.existsSync(source)) return; // not vendored (pi-injected or absent)
      const target = path.join(packageDir, 'node_modules', depName);
      if (fs.existsSync(target)) return; // npm already nested it
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.symlinkSync(path.relative(path.dirname(target), source), target, 'dir');
      links += 1;
    };

    // Process the managed package itself plus the direct children of its
    // node_modules: npm nests their dependencies under them, but their
    // PEERS dangle (e.g. @xterm/addon-serialize -> @xterm/xterm).
    const manifestDirs = [];
    for (const packageDir of process.argv.slice(3)) {
      manifestDirs.push(packageDir);
      const nested = path.join(packageDir, 'node_modules');
      if (!fs.existsSync(nested)) continue;
      for (const scope of fs.readdirSync(nested)) {
        if (scope.startsWith('@')) {
          const scopeDir = path.join(nested, scope);
          if (!fs.existsSync(scopeDir)) continue;
          for (const name of fs.readdirSync(scopeDir)) {
            manifestDirs.push(path.join(scopeDir, name));
          }
        } else {
          manifestDirs.push(path.join(nested, scope));
        }
      }
    }

    for (const packageDir of manifestDirs) {
      const manifestPath = path.join(packageDir, 'package.json');
      if (!fs.existsSync(manifestPath)) continue;
      const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
      for (const depName of [
        ...Object.keys(manifest.dependencies ?? {}),
        ...Object.keys(manifest.peerDependencies ?? {}),
      ]) {
        if (injected.has(depName)) continue;
        linkInto(packageDir, depName);
      }
    }
    console.log(`ensure-self-contained: created ''${links} dependency links`);
  '';

  # Build the complete managed-package agent artifacts (facades, sources,
  # declarations/report/install-state) for a given package selection.
  makePiManagedPackages = { includeGitNexus ? false, powerlineTheme ? defaultPowerlineTheme }:
    let
      enabledPackages = lib.filterAttrs
        (packageId: _: includeGitNexus || packageId != "pi-gitnexus")
        managedPackages;
      enabledIds = lib.attrNames enabledPackages;

      themeFile = pkgs.writeText "pi-powerline-footer-theme.json"
        (builtins.toJSON powerlineTheme);

      declarationsFile = pkgs.writeText "pi-managed-declarations.json" (builtins.toJSON {
        packages = map (packageId: {
          inherit packageId;
          source = enabledPackages.${packageId}.source // {
            materializedPath = "./vendor/node_modules/${enabledPackages.${packageId}.source.packageName}";
          };
        } // lib.optionalAttrs (enabledPackages.${packageId} ? expose) {
          expose = enabledPackages.${packageId}.expose;
        }) enabledIds;
      });

      # .pi-managed-install.json required by the install-state helper for
      # git sources (installedCommit / requestedRefType).
      gitMetadataFile = rev: pkgs.writeText "pi-managed-install.json" (builtins.toJSON {
        schemaVersion = 1;
        installedCommit = rev;
        requestedRefType = "commit";
      });

      installGitPackage = packageName: let
        pin = gitSources.${packageName};
      in ''
        rm -rf "$out/vendor/node_modules/${packageName}"
        cp -r --no-preserve=mode,ownership ${pin.tarball} "$out/vendor/node_modules/${packageName}"
        cp ${gitMetadataFile pin.rev} "$out/vendor/node_modules/${packageName}/.pi-managed-install.json"
      '';
    in
    pkgs.runCommand "pi-managed-packages" {
      nativeBuildInputs = [ nodejs ];
      # Fixed timestamp keeps install-state.json byte-reproducible.
      generatedAt = "1970-01-01T00:00:00.000Z";
    } ''
      set -euo pipefail
      mkdir -p "$out/vendor" "$out/agent"

      # 1. Materialize the npm vendor tree (writable copy).
      # --no-preserve: store sources are read-only; the vendor copy must be writable
      cp -r --no-preserve=mode,ownership ${piVendor}/node_modules "$out/vendor/node_modules"

      # 2. Place git-pinned packages with their install metadata.
      ${lib.concatMapStrings (packageName: installGitPackage packageName)
        (lib.unique (map (packageId: enabledPackages.${packageId}.source.packageName)
          (lib.filter (packageId: enabledPackages.${packageId}.source.type == "git") enabledIds)))}

      # 4. Guarantee per-package self-containment (see
      #    ensureSelfContainedScript above for why).
      node ${ensureSelfContainedScript} \
        "$out/vendor/node_modules" \
        ${lib.concatMapStringsSep " " (packageName:
          "\"$out/vendor/node_modules/${packageName}\""
        ) (lib.unique (map (packageId: enabledPackages.${packageId}.source.packageName) enabledIds))}

      # 5. Apply the powerline theme override at build time. Powerline
      #    resolves theme.json relative to its extension module; the vendor
      #    tree is the only writable location before facades become
      #    read-only store paths.
      if [ -d "$out/vendor/node_modules/pi-powerline-footer" ]; then
        cp ${themeFile} "$out/vendor/node_modules/pi-powerline-footer/theme.json"
      fi

      # 6. Compile facades + install state (materializedPath entries are
      #    relative to this declarations file, i.e. inside $out).
      cp ${declarationsFile} "$out/declarations.json"
      node ${self}/nix/modules/pi/compile-managed-packages.mjs \
        --declarations "$out/declarations.json" \
        --output-dir "$out/agent" > "$out/agent/managed-packages.report.json"
      node ${self}/nix/modules/pi/build-managed-package-install-state.mjs \
        --declarations "$out/declarations.json" \
        --generated-at "$generatedAt" > "$out/agent/managed-packages.install-state.json"
      cp "$out/declarations.json" "$out/agent/managed-packages.declarations.json"
    '';

  # Pi runtime package list (settings.json `packages`) for a footer choice.
  makePiRuntimePackageIds = { footer ? "powerline", includeGitNexus ? false }:
    let
      enabledIds = lib.filter (packageId: includeGitNexus || packageId != "pi-gitnexus")
        (lib.attrNames managedPackages);
      selectedFooterPackageId = if footer == "powerline" then "pi-powerline-footer" else "pi-zentui";
    in
    lib.filter (packageId:
      managedPackages.${packageId}.source.type != "local"
      && (!lib.elem packageId footerPackageIds || packageId == selectedFooterPackageId)
    ) enabledIds;

  # ============================================================
  # settings.json body (shared by HM shim and NixOS shim)
  # ============================================================
  makePiSettings = { defaultProvider ? "zai-coding-plan", defaultModel ? "glm-5.2"
    , defaultThinkingLevel ? "medium", theme ? "catppuccin-mocha"
    , footer ? "powerline", enabledModels ? defaultEnabledModels
    , includeGitNexus ? false
    , powerline ? defaultPowerlineConfig, powerlineShortcuts ? defaultPowerlineShortcuts
    , subagentDefaultModel ? null, subagentOverrides ? { }
    }:
    {
      inherit defaultProvider defaultModel defaultThinkingLevel theme;
      quietStartup = false;
      hideThinkingBlock = false;

      compaction = {
        enabled = true;
        reserveTokens = 16384;
        keepRecentTokens = 20000;
      };

      thinkingBudgets = {
        low = 4096;
        medium = 8192;
        high = 32768;
      };

      enableSkillCommands = true;

      lsp = {
        hookMode = "agent_end";
      };

      inherit enabledModels;

      packages = map (packageId: "./packages/${packageId}")
        (makePiRuntimePackageIds { inherit footer includeGitNexus; });

      # pi-subagents routing. disableBuiltins keeps the extension's bundled
      # agents out; the shipped repo agents (agents/*.md) are custom agents.
      # subagentDefaultModel applies only to agents WITHOUT an explicit model;
      # subagentOverrides (subagents.agentOverrides) fields are SKIPPED for
      # any field an agent's frontmatter already declares — use makePiConfig's
      # agentOverrides to re-point frontmatter-declared models per consumer.
      subagents = { disableBuiltins = true; }
        // lib.optionalAttrs (subagentDefaultModel != null) {
          defaultModel = subagentDefaultModel;
        }
        // lib.optionalAttrs (subagentOverrides != { }) {
          agentOverrides = subagentOverrides;
        };
    } // lib.optionalAttrs (footer == "powerline") {
      inherit powerline powerlineShortcuts;
    };

  # ============================================================
  # Static agent files (identical content in every consumer tree)
  # ============================================================
  piStaticFiles = {
    keybindings = builtins.toJSON {
      "tui.select.up" = [ "up" "ctrl+p" ];
      "tui.select.down" = [ "down" "ctrl+n" ];
      "app.model.cycleForward" = [ "alt+]" ];
      "app.model.cycleBackward" = [ "alt+[" ];
      "app.model.select" = [ "alt+l" ];
      "app.thinking.cycle" = [ "ctrl+t" ];
      "app.thinking.toggle" = [ "ctrl+shift+t" ];
    };

    catppuccinMochaTheme = ''
      {
        "$schema": "https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json",
        "name": "catppuccin-mocha",
        "vars": {
          "rosewater": "#f5e0dc", "flamingo": "#f2cdcd", "pink": "#f5c2e7",
          "mauve": "#cba6f7", "red": "#f38ba8", "maroon": "#eba0ac",
          "peach": "#fab387", "yellow": "#f9e2af", "green": "#a6e3a1",
          "teal": "#94e2d5", "sky": "#89dceb", "sapphire": "#74c7ec",
          "blue": "#89b4fa", "lavender": "#b4befe", "text": "#cdd6f4",
          "subtext": "#a6adc8", "overlay": "#6c7086", "surface2": "#6c7086",
          "surface1": "#585b70", "surface0": "#45475a", "surface": "#313244",
          "base": "#1e1e2e", "mantle": "#181825", "crust": "#11111b"
        },
        "colors": {
          "accent": "lavender", "border": "blue", "borderAccent": "sky",
          "borderMuted": "surface0", "success": "green", "error": "red",
          "warning": "peach", "muted": "overlay", "dim": "surface2",
          "text": "text", "thinkingText": "subtext", "selectedBg": "surface",
          "userMessageBg": "surface", "userMessageText": "text",
          "customMessageBg": "surface", "customMessageText": "text",
          "customMessageLabel": "mauve", "toolPendingBg": "mantle",
          "toolSuccessBg": "#394545", "toolErrorBg": "#483346",
          "toolTitle": "lavender", "toolOutput": "subtext",
          "mdHeading": "yellow", "mdLink": "blue", "mdLinkUrl": "overlay",
          "mdCode": "peach", "mdCodeBlock": "green", "mdCodeBlockBorder": "surface1",
          "mdQuote": "overlay", "mdQuoteBorder": "surface1", "mdHr": "surface1",
          "mdListBullet": "teal", "toolDiffAdded": "green", "toolDiffRemoved": "red",
          "toolDiffContext": "overlay", "syntaxComment": "surface2",
          "syntaxKeyword": "mauve", "syntaxFunction": "blue", "syntaxVariable": "flamingo",
          "syntaxString": "green", "syntaxNumber": "peach", "syntaxType": "teal",
          "syntaxOperator": "rosewater", "syntaxPunctuation": "overlay",
          "thinkingOff": "surface0", "thinkingMinimal": "surface1",
          "thinkingLow": "blue", "thinkingMedium": "sapphire",
          "thinkingHigh": "mauve", "thinkingXhigh": "pink", "bashMode": "green"
        },
        "export": {
          "pageBg": "#11111b", "cardBg": "#181825", "infoBg": "#313244",
          "text": "#cdd6f4", "muted": "#6c7086"
        }
      }
    '';

    claudeMd = ''
      ## Claude Guidance

      You are an expert coding assistant. Follow the same principles as usual:
      - Think step-by-step before edits
      - Prefer simplicity and readability
      - Verify changes work before completing tasks
    '';

    codexMd = ''
      ## GPT-Optimized Guidance (injected only for OpenAI Codex models)

      You are a senior, pragmatic, production-focused software engineer with 15+ years experience shipping reliable systems.

      **Core principles (always follow):**
      - Think step-by-step BEFORE any tool call or edit. Never guess file contents — read first.
      - Prefer simplicity, readability, and idiomatic code over cleverness.
      - For every non-trivial change: (1) plan, (2) implement with tools, (3) verify (run tests/build/lint), (4) reflect and fix if needed.
      - Be extremely precise with tool arguments. If unsure about a path or command, read/explore first.
      - Output format: after major edits, always summarize what changed and why in a clear bullet list.
      - If a task might take >10 tool calls, break it into verifiable milestones and confirm with me before continuing.

      **Tool-use style (OpenAI-specific):**
      - You excel at parallel tool use when safe. Group independent reads/edits.
      - For code edits, use the smallest possible targeted edit (the Edit tool loves precise hunks).
      - When reasoning is heavy, keep internal thoughts concise — the model already has strong chain-of-thought.

      **Never hallucinate completion.** If blocked or unsure, say so clearly and suggest the next best action or sub-task.

      Current stack/context will be provided below. Always respect it.
    '';

    models = builtins.toJSON {
      providers = {
        zai-coding-plan = {
          apiKey = "$ZAI_API_KEY";
          baseUrl = "https://api.z.ai/api/coding/paas/v4";
          api = "openai-completions";
          models = [
            { id = "glm-5.3"; name = "GLM 5.3"; contextWindow = 1000000; maxTokens = 131072; reasoning = true; }
            { id = "glm-5.2"; name = "GLM 5.2"; contextWindow = 1048576; maxTokens = 131072; reasoning = true; }
            { id = "glm-5.1"; name = "GLM 5.1"; contextWindow = 204800; maxTokens = 131072; reasoning = true; }
            { id = "glm-5"; name = "GLM 5"; contextWindow = 204800; maxTokens = 131072; reasoning = true; }
            { id = "glm-5-turbo"; name = "GLM 5 Turbo"; contextWindow = 200000; maxTokens = 131072; reasoning = true; }
            { id = "glm-4.7"; name = "GLM 4.7"; contextWindow = 204800; maxTokens = 131072; reasoning = true; }
            { id = "glm-4.7-flash"; name = "GLM 4.7 Flash"; contextWindow = 131072; maxTokens = 8192; }
            { id = "glm-4.6v"; name = "GLM 4.6 Vision"; contextWindow = 131072; maxTokens = 16384; input = [ "text" "image" ]; }
            { id = "glm-4.5v"; name = "GLM 4.5 Vision"; contextWindow = 131072; maxTokens = 16384; input = [ "text" "image" ]; }
            { id = "glm-4.6"; name = "GLM 4.6"; contextWindow = 131072; maxTokens = 16384; }
            { id = "glm-4.5"; name = "GLM 4.5"; contextWindow = 131072; maxTokens = 16384; }
            { id = "glm-4.5-air"; name = "GLM 4.5 Air"; contextWindow = 131072; maxTokens = 8192; }
            { id = "glm-4.5-flash"; name = "GLM 4.5 Flash"; contextWindow = 131072; maxTokens = 8192; }
          ];
        };

        # PI-VERSION-OVERLAY: Temporary compatibility overlay for Pi 0.80.7's
        # bundled Copilot catalog. Remove it when the Pi version we adopt
        # includes `claude-opus-5` in its built-in github-copilot catalog; a custom model
        # with the same id replaces the packaged definition. The provider's
        # built-in OAuth configuration remains in effect.
        github-copilot = {
          models = [
            {
              id = "claude-opus-5";
              name = "Claude Opus 5";
              api = "anthropic-messages";
              # Copilot requires this IDE identity on every request, including
              # requests for models added outside Pi's bundled catalog.
              headers = {
                "User-Agent" = "GitHubCopilotChat/0.35.0";
                "Editor-Version" = "vscode/1.107.0";
                "Editor-Plugin-Version" = "copilot-chat/0.35.0";
                "Copilot-Integration-Id" = "vscode-chat";
              };
              reasoning = true;
              thinkingLevelMap = {
                minimal = "low";
                xhigh = "xhigh";
                max = "max";
              };
              input = [ "text" "image" ];
              contextWindow = 1048576;
              maxTokens = 128000;
              compat = {
                forceAdaptiveThinking = true;
                supportsTemperature = false;
              };
            }
          ];
        };
      };
    };

    mcp = builtins.toJSON {
      mcpServers = {
        "web-search-prime" = {
          type = "http";
          url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
          headers = { Authorization = "Bearer {env:ZAI_API_KEY}"; };
          lifecycle = "lazy";
          idleTimeout = 10;
        };
        "web-reader" = {
          type = "http";
          url = "https://api.z.ai/api/mcp/web_reader/mcp";
          headers = { Authorization = "Bearer {env:ZAI_API_KEY}"; };
          lifecycle = "lazy";
          idleTimeout = 10;
        };
        "zread" = {
          type = "http";
          url = "https://api.z.ai/api/mcp/zread/mcp";
          headers = { Authorization = "Bearer {env:ZAI_API_KEY}"; };
          lifecycle = "lazy";
          idleTimeout = 10;
        };
        "zai-vision" = {
          command = "npx";
          args = [ "-y" "@z_ai/mcp-server" ];
          env = {
            Z_AI_API_KEY = "{env:ZAI_API_KEY}";
            Z_AI_MODE = "ZAI";
          };
          lifecycle = "lazy";
          enabled = false;
        };
      };
      settings = {
        toolPrefix = "server";
        idleTimeout = 10;
      };
    };
  };

  # Repo-owned assets linked into every agent tree.
  repoRoot = "${self}";

  # Patch a shipped agent definition's frontmatter at build time (the pi
  # analogue of opencode's agentModelOverrides). Settings-level
  # subagents.agentOverrides cannot re-point fields an agent's frontmatter
  # already declares — per-consumer routing of frontmatter-declared models
  # (model:, fallbackModels:, thinking:) goes through this patch instead.
  # Unspecified fields pass through unchanged; the derivation self-verifies.
  patchAgentMd = name: override:
    let
      fallbacks = lib.concatStringsSep ", " (override.fallbackModels or [ ]);
    in
    pkgs.runCommand "pi-agent-${name}-patched.md" {
      model = override.model or "";
      inherit fallbacks;
      thinking = override.thinking or "";
    } ''
      set -euo pipefail
      awk -v m="$model" -v fb="$fallbacks" -v th="$thinking" '
        NR==1 && $0 == "---" { infm=1; print; next }
        infm && $0 == "---" {
          if (m != "" && !sawmodel) print "model: " m
          if (fb != "" && !donefb) print "fallbackModels: " fb
          infm=0; print; next
        }
        infm && /^model:[[:space:]]/ {
          sawmodel=1
          if (m != "") print "model: " m; else print
          if (fb != "") { print "fallbackModels: " fb; donefb=1 }
          next
        }
        infm && /^fallbackModels:[[:space:]]/ {
          if (fb != "" && !donefb) { print "fallbackModels: " fb; donefb=1 }
          else if (fb == "") print
          next
        }
        infm && /^thinking:[[:space:]]/ {
          if (th != "") print "thinking: " th; else print
          next
        }
        { print }
      ' ${repoRoot}/agents/${name}.md > $out

      ${lib.optionalString (override ? model) ''
        grep -Fqx "model: ${override.model}" $out || { echo "agentOverrides: model patch failed for ${name}" >&2; exit 1; }
      ''}
      ${lib.optionalString (override ? fallbackModels) ''
        grep -Fqx "fallbackModels: ${fallbacks}" $out || { echo "agentOverrides: fallbackModels patch failed for ${name}" >&2; exit 1; }
      ''}
      ${lib.optionalString (override ? thinking) ''
        grep -Fqx "thinking: ${override.thinking}" $out || { echo "agentOverrides: thinking patch failed for ${name}" >&2; exit 1; }
      ''}
    '';

  piSkills = [
    "discovery"
    "design"
    "research"
    "create-plan"
    "review-plan"
    "create-worklog"
    "execute-task"
    "execution-orchestrator"
    "review-code"
    "review-approach"
    "assess-repo"
    "create-skills"
    "configure-pi"
    "create-new-repo-docs"
    "pi-team-plan"
    "pi-team-lead"
    "pi-team-worker"
  ];

  piAgents = [
    "planner"
    "plan-reviewer"
    "code-reviewer"
    "worker"
    "ui-worker"
    "researcher"
    "vision"
    "oracle"
    "pi-team-reviewer"
  ];

in
{
  # Repo-owned asset lists (consumed by both shims so the rosters have one
  # source of truth).
  piAgentNames = piAgents;
  piSkillNames = piSkills;

  inherit
    managedPackages
    makePiManagedPackages
    makePiRuntimePackageIds
    makePiSettings
    piStaticFiles
    defaultEnabledModels
    defaultPowerlineConfig
    defaultPowerlineShortcuts
    defaultPowerlineTheme
    footerPackageIds;

  # Complete static agent tree (everything except managed packages and the
  # consumer-writable settings.json/guardrails.json). Consumers that need the
  # managed packages link the separate makePiManagedPackages output.
  #
  # Usage:
  #   makePiConfig {}                                        # defaults
  #   makePiConfig { defaultModel = "glm-5.2"; footer = "zentui"; }
  #   makePiConfig { extraSkills.visual-explainer = "<store path>"; }
  makePiConfig = args@{
    defaultProvider ? "zai-coding-plan",
    defaultModel ? "glm-5.2",
    defaultThinkingLevel ? "medium",
    theme ? "catppuccin-mocha",
    footer ? "powerline",
    enabledModels ? defaultEnabledModels,
    includeGitNexus ? false,
    powerline ? defaultPowerlineConfig,
    powerlineShortcuts ? defaultPowerlineShortcuts,
    extraSkills ? {},
    # Per-consumer agent routing: attrset of <agentName> -> { model ?,
    # fallbackModels ? [ ... ], thinking ? } patched into the shipped agent
    # frontmatter at build time. Wins over the shipped frontmatter (unlike
    # subagentOverrides, which frontmatter-declared fields ignore).
    agentOverrides ? {},
    subagentDefaultModel ? null,
    subagentOverrides ? {},
    ...
  }:
  let
    unknownAgentOverrides =
      lib.filter (n: !lib.elem n piAgents) (lib.attrNames agentOverrides);
  in
  assert lib.assertMsg (unknownAgentOverrides == [])
    "makePiConfig agentOverrides references unknown agents: ${toString unknownAgentOverrides} (known: ${toString piAgents})";
  let
    settings = makePiSettings {
      inherit
        defaultProvider
        defaultModel
        defaultThinkingLevel
        theme
        footer
        enabledModels
        includeGitNexus
        powerline
        powerlineShortcuts
        subagentDefaultModel
        subagentOverrides;
    };
  in
  pkgs.runCommand "pi-agent-config" {} ''
    mkdir -p $out/agent/{themes,agents,skills,messenger/team-profiles,extensions}

    cp ${pkgs.writeText "pi-settings-nix.json" (builtins.toJSON settings)} $out/agent/settings.json
    cp ${pkgs.writeText "pi-keybindings.json" piStaticFiles.keybindings} $out/agent/keybindings.json
    cp ${pkgs.writeText "pi-models.json" piStaticFiles.models} $out/agent/models.json
    cp ${pkgs.writeText "pi-mcp.json" piStaticFiles.mcp} $out/agent/mcp.json
    cp ${pkgs.writeText "catppuccin-mocha.json" piStaticFiles.catppuccinMochaTheme} $out/agent/themes/catppuccin-mocha.json
    cp ${pkgs.writeText "CLAUDE.md" piStaticFiles.claudeMd} $out/agent/CLAUDE.md
    cp ${pkgs.writeText "CODEX.md" piStaticFiles.codexMd} $out/agent/CODEX.md

    # guardrails.json is consumer-writable (the extension persists confirmed
    # decisions); shims copy it in, they must not symlink it.
    cp ${repoRoot}/nix/modules/pi/guardrails.json $out/agent/guardrails.json

    ln -s ${repoRoot}/agents/preset.jsonc $out/agent/preset.jsonc
    ln -s ${repoRoot}/config/pi-team/team-profile.json $out/agent/messenger/team-profiles/pi-team.json
    ln -s ${repoRoot}/nix/modules/pi/extensions/startup-staleness-warning $out/agent/extensions/startup-staleness-warning

    ${lib.concatMapStringsSep "\n  " (name:
      "ln -s ${
        if agentOverrides ? ${name}
        then patchAgentMd name agentOverrides.${name}
        else "${repoRoot}/agents/${name}.md"
      } $out/agent/agents/${name}.md"
    ) piAgents}

    ${lib.concatMapStringsSep "\n  " (name:
      "ln -s ${repoRoot}/dist/skills/pi/${name} $out/agent/skills/${name}"
    ) piSkills}

    ${lib.concatMapStringsSep "\n  " (name:
      "ln -s ${extraSkills.${name}} $out/agent/skills/${name}"
    ) (lib.attrNames extraSkills)}
  '';
}
