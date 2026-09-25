# nix/modules/pi/pi-lens-tools.nix — Nix-supplied binaries for pi-lens
#
# pi-lens auto-installs its language servers, linters and scanners at
# runtime (npm/pip/go install, GitHub release downloads). The managed policy
# (extensions/pi-lens-policy) disables that and instead appends this
# environment's bin/ to pi's own PATH, so pi-lens finds pinned binaries on
# every launch path (terminal, Hermes service, subagent children) without
# changing the user's shell PATH. Project/devshell tools earlier on PATH
# (e.g. a repo's node_modules/.bin biome) still win.
#
# Selection:
# - Language servers and linters for the languages pi-lens dispatches.
#   Most linters are config-gated: they only run when a project has their
#   config or dependency, so shipping them is inert elsewhere.
# - Scanners: gitleaks, govulncheck (runs only with go.mod; needs the
#   project's Go toolchain), ast-grep, opengrep; knip/jscpd/madge come from
#   the managed npm vendor tree.
# - nixfmt is deliberately absent: pi-lens has no lint use for it and would
#   run it as the .nix formatter whenever it is on PATH, restyling whole
#   files once a repo opts into format (format/autofix stay a per-project
#   opt-in, see pi-lens.json). shfmt is included: its lint check is a
#   read-only `shfmt --diff`, and as a formatter it keeps the file's own
#   indentation.
{ pkgs, pkgsUnstable, piVendor }:

let
  # opengrep ships a Nuitka onefile self-extractor. The upstream flake is a
  # full OCaml/opam development build, so package the signed release binary
  # instead: extract once at build time, then patch the unpacked standalone
  # tree for NixOS (glibc interpreter + zlib, which binascii.so links but the
  # bundle does not carry). Its other shared libraries are bundled.
  opengrep = pkgs.stdenv.mkDerivation rec {
    pname = "opengrep";
    version = "1.30.0";

    src = pkgs.fetchurl {
      url = "https://github.com/opengrep/opengrep/releases/download/v${version}/opengrep_manylinux_x86";
      hash = "sha256-NXeb3XLpISnI3yp38MVejAg1aAHqklke8yEI1rKNVkw=";
    };

    dontUnpack = true;
    nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.makeBinaryWrapper ];
    buildInputs = [ pkgs.zlib pkgs.stdenv.cc.cc.lib ];

    buildPhase = ''
      runHook preBuild
      export HOME="$NIX_BUILD_TOP/home"
      install -m 0755 "$src" onefile
      # The loader itself needs the glibc interpreter to run in the sandbox
      # (patching it keeps the appended payload intact).
      patchelf --set-interpreter "$(cat "$NIX_CC/nix-support/dynamic-linker")" onefile
      # The loader extracts to $HOME/.cache/opengrep/v<version>/ and then
      # execs the unpatched payload, which fails here; only the extraction
      # matters.
      ./onefile --version >/dev/null 2>&1 || true
      test -x "$HOME/.cache/opengrep/v${version}/opengrep.bin"
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib" "$out/bin"
      cp -r "$HOME/.cache/opengrep/v${version}" "$out/lib/opengrep"
      makeBinaryWrapper "$out/lib/opengrep/opengrep.bin" "$out/bin/opengrep"
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      export HOME="$NIX_BUILD_TOP/check-home"
      test "$("$out/bin/opengrep" --version)" = "${version}"
    '';

    meta = {
      description = "Opengrep static analysis CLI (release binary)";
      homepage = "https://github.com/opengrep/opengrep";
      license = pkgs.lib.licenses.lgpl21Only;
      platforms = [ "x86_64-linux" ];
      sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
    };
  };

  # npm bin scripts use `#!/usr/bin/env node`; wrap them with Nix's node
  # so they also run where PATH has no node (e.g. the Hermes service).
  vendorBins = pkgs.runCommand "pi-lens-vendor-bins" {
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
  } ''
    mkdir -p "$out/bin"
    for tool in knip jscpd madge; do
      script="$(readlink -f "${piVendor}/node_modules/.bin/$tool")"
      test -f "$script"
      makeBinaryWrapper "${pkgs.nodejs}/bin/node" "$out/bin/$tool" --add-flags "$script"
      "$out/bin/$tool" --version >/dev/null
    done
  '';

  u = pkgsUnstable;
in
pkgs.buildEnv {
  name = "pi-lens-tools";
  pathsToLink = [ "/bin" ];
  paths = [
    # Language servers. Those the host commonly installs itself come from
    # the consumer's pkgs so they dedupe with the system copy (unstable nixd
    # alone would add ~540 MiB of LLVM).
    pkgs.typescript-language-server
    pkgs.svelte-language-server
    pkgs.nixd
    pkgs.lua-language-server
    u.typescript
    u.vue-language-server
    u.vscode-langservers-extracted
    u.yaml-language-server
    u.bash-language-server
    u.dockerfile-language-server
    u.pyright
    u.taplo
    u.typos-lsp
    # Linters (mostly config-gated)
    u.biome
    u.ruff
    u.shellcheck
    u.shfmt
    u.oxlint
    u.zizmor
    u.yamllint
    u.actionlint
    u.hadolint
    u.markdownlint-cli2
    u.stylelint
    u.htmlhint
    u.sqlfluff
    u.tflint
    u.golangci-lint
    # Scanners
    u.gitleaks
    u.govulncheck
    u.ast-grep
    opengrep
    vendorBins
  ];
  # gitleaks also ships a generic `config` helper; keep it off PATH.
  postBuild = ''
    rm -f "$out/bin/config"
  '';
  passthru = { inherit opengrep; };
}
