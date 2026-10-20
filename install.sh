#!/usr/bin/env bash
# NeoGaeshi — one-liner bootstrap installer (Linux).
#
# Installs the complete NeoGaeshi blue-team profile:
#   1. prerequisites (git, curl, node, npm — via your package manager if needed)
#   2. engram (local persistent memory, MCP server)
#      https://github.com/Gentleman-Programming/engram
#   3. OpenCode V1 runtime 1.19.3 (isolated, ~/.local/share/opencode-v1)
#      — the default NeoGaeshi product line (branded logo, blue-team analyst)
#   4. this repo -> ~/.local/share/neogaeshi (the profile root)
#   5. the hermetic V1 profile + the `neogaeshi` CLI (~/.local/bin/neogaeshi)
#
# Optional (opt-in, OFF by default):
#   - OpenCode V2 (system, official installer -> ~/.opencode/bin)
#     https://github.com/anomalyco/opencode (formerly sst/opencode)
#     Compatibility line for users who already run OpenCode 2.x; install it
#     with --with-v2. OpenCode 2.x has no logo-replacement slot, so the V2
#     line cannot carry the NeoGaeshi brand — V1 is the product.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/naiamproducts/neogaeshi/main/install.sh | bash
#   bash install.sh [--with-auth] [--with-v2] [--force] [--uninstall] [--update] [--update-v2] [--help]
#
# Flags:
#   --with-auth    copy an existing ~/.local/share/opencode/auth.json into the
#                  isolated V1 profile (OFF by default; never touches the original)
#   --with-v2      also install the system OpenCode V2 (official installer ->
#                  ~/.opencode/bin). Skipped by default: OpenCode V1 is the
#                  default NeoGaeshi line; V2 is a compatibility line
#   --force        back up and replace a conflicting ~/.local/bin/neogaeshi entry
#   --uninstall    remove NeoGaeshi (symlink, profile config, V1 runtime, repo
#                  copy). Never touches your global opencode config or data,
#                  and leaves the general-purpose engram/opencode binaries alone
#   --update       update mode (run by `neogaeshi update`): fast-forward the
#                  repo copy at NEOGAESHI_ROOT from origin and re-sync the
#                  hermetic V1 profile config. Installed config files that
#                  differ from the incoming templates are backed up first (as
#                  <file>.bak.<timestamp>). Refuses to run over local
#                  modifications or a diverged checkout. Never touches the V1
#                  runtime, engram, or your global opencode config/data
#   --update-v2    pull-only update (run by `neogaeshi update --v2`): the V2
#                  profile IS the repo checkout, so pulling updates it in place
#   --help         show this help
#
# Environment (mostly for testing):
#   NEOGAESHI_ROOT            install location of the repo copy
#                             (default: ~/.local/share/neogaeshi)
#   NEOGAESHI_SOURCE          local directory to copy instead of git-cloning
#                             (for pre-release testing; the default is the
#                             GitHub repo above)
#   NEOGAESHI_SKIP_ENGRAM=1   skip the engram download (expects it already present)
#   NEOGAESHI_SKIP_OPENCODE=1 skip the OpenCode V2 install (expects opencode on PATH)
#   NEOGAESHI_SKIP_RUNTIME=1  skip the isolated OpenCode V1 runtime install
set -euo pipefail

REPO_URL="https://github.com/naiamproducts/neogaeshi"
NEOGAESHI_ROOT="${NEOGAESHI_ROOT:-$HOME/.local/share/neogaeshi}"
V1_VERSION="1.19.3"
V1_PREFIX="$HOME/.local/share/opencode-v1"
BIN_DIR="$HOME/.local/bin"
CONFIG_ROOT="$HOME/.config/neogaeshi-v1"

# Make user-local bins visible inside this run (installed tools must be
# verifiable even when ~/.local/bin is not on PATH yet).
ORIGINAL_PATH="$PATH"   # the user's own shell PATH, kept for shadow checks
export PATH="$BIN_DIR:$HOME/.opencode/bin:$PATH"

# --- Presentation -----------------------------------------------------------
VIOLET=$'\033[38;5;141m'
MUTED=$'\033[38;5;245m'
BOLD=$'\033[1m'
RED=$'\033[38;5;203m'
RESET=$'\033[0m'
info() { printf '  %s•%s %s\n' "$VIOLET" "$RESET" "$*"; }
ok()   { printf '  %s✔%s %s\n' "$VIOLET" "$RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$RED" "$RESET" "$*" >&2; }
fail() { printf '\n%s✘ %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

usage() {
  awk 'NR>1 && /^set -euo pipefail/{exit} NR>1{sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"
}

# --- Flags ------------------------------------------------------------------
WITH_AUTH=0
WITH_V2=0
FORCE=0
UNINSTALL=0
UPDATE=0
UPDATE_V2=0
for arg in "$@"; do
  case "$arg" in
    --with-auth) WITH_AUTH=1 ;;
    --with-v2) WITH_V2=1 ;;
    --force) FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --update) UPDATE=1 ;;
    --update-v2) UPDATE_V2=1 ;;
    --help|-h) usage; exit 0 ;;
    *) printf '%sUnknown option: %s (see --help)%s\n' "$RED" "$arg" "$RESET" >&2; exit 1 ;;
  esac
done
if [[ "$UPDATE" == "1" && "$UPDATE_V2" == "1" ]]; then
  printf '%sOptions --update and --update-v2 are mutually exclusive (see --help)%s\n' "$RED" "$RESET" >&2
  exit 1
fi

# --- Sudo helper (only ever used for the required packages) -----------------
SUDO_OK=0
need_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then SUDO_OK=0; return; fi  # 0 = run directly
  if command -v sudo >/dev/null 2>&1; then
    info "This step needs root to install missing packages via the system package manager"
    sudo -v || fail "sudo authentication failed"
    SUDO_OK=1
    return
  fi
  fail "Missing required tools and no sudo available. Install them manually, then re-run:
  - git, curl, node (>=18), npm
  Debian/Ubuntu:  sudo apt-get install -y git curl nodejs npm
  Fedora:         sudo dnf install -y git curl nodejs npm
  Arch:           sudo pacman -S --noconfirm git curl nodejs npm
  openSUSE:       sudo zypper -n install git curl nodejs npm"
}
as_root() {
  if [[ "$SUDO_OK" == "1" ]]; then sudo "$@"; else "$@"; fi
}

# --- 1. Preflight -----------------------------------------------------------
preflight() {
  printf '\n%sNeoGaeshi installer%s — blue-team profile for OpenCode\n\n' "$VIOLET" "$RESET"

  [[ "$(uname -s)" == "Linux" ]] || fail "NeoGaeshi currently supports Linux only (detected: $(uname -s))."

  local arch
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) fail "Unsupported architecture: $(uname -m) (supported: x86_64, aarch64)" ;;
  esac
  ARCH="$arch"

  local pkgmgr=""
  for m in apt-get dnf pacman zypper; do
    if command -v "$m" >/dev/null 2>&1; then pkgmgr="$m"; break; fi
  done
  PKGMGR="$pkgmgr"
  info "Platform: linux/$ARCH (pkg manager: ${pkgmgr:-none detected})"

  # Ensure required tools; install missing ones via the pkg manager.
  local missing=() c
  for c in git curl node npm; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    info "Missing required tools: ${missing[*]}"
    need_sudo
    local pkgs=()
    for c in "${missing[@]}"; do
      case "$c" in
        node|npm) pkgs+=(nodejs npm) ;;
        *) pkgs+=("$c") ;;
      esac
    done
    # shellcheck disable=SC2207
    mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
    info "Installing via $PKGMGR: ${pkgs[*]}"
    case "$PKGMGR" in
      apt-get) as_root apt-get update -qq && as_root apt-get install -y "${pkgs[@]}" ;;
      dnf)     as_root dnf install -y "${pkgs[@]}" ;;
      pacman)  as_root pacman -S --noconfirm --needed "${pkgs[@]}" ;;
      zypper)  as_root zypper -n install "${pkgs[@]}" ;;
      *) fail "No supported package manager found to install: ${pkgs[*]}" ;;
    esac
    for c in "${missing[@]}"; do
      command -v "$c" >/dev/null 2>&1 || fail "'$c' is still missing after installation. Install it manually and re-run."
    done
  fi
  ok "Prerequisites present: git, curl, node ($(node --version 2>/dev/null || true)), npm"
}

# --- 2. engram --------------------------------------------------------------
install_engram() {
  printf '\n%s[1/4]%s engram (persistent memory)\n' "$VIOLET" "$RESET"

  if [[ -x "$BIN_DIR/engram" ]] && "$BIN_DIR/engram" --version >/dev/null 2>&1; then
    ok "engram already present ($("$BIN_DIR/engram" --version 2>/dev/null | head -1)), skipping download"
    ENGRAM_BIN="$BIN_DIR/engram"
    return
  fi
  if [[ "${NEOGAESHI_SKIP_ENGRAM:-0}" == "1" ]]; then
    warn "NEOGAESHI_SKIP_ENGRAM=1 set but no engram at $BIN_DIR/engram; falling back to PATH"
    ENGRAM_BIN="$(command -v engram || true)"
    [[ -n "$ENGRAM_BIN" ]] || fail "NEOGAESHI_SKIP_ENGRAM=1 but engram was not found on PATH"
    return
  fi

  info "Resolving latest engram release from GitHub..."
  local api asset version
  api="$(curl -fsSL https://api.github.com/repos/Gentleman-Programming/engram/releases/latest)" \
    || fail "Could not reach the engram GitHub releases API. Check your network (or set NEOGAESHI_SKIP_ENGRAM=1 if engram is already installed)."
  version="$(printf '%s' "$api" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)"
  [[ -n "$version" ]] || fail "Could not parse the latest engram release tag from the GitHub API"
  # Asset naming: engram_<version>_linux_<amd64|arm64>.tar.gz
  asset="$(printf '%s' "$api" | grep -o '"browser_download_url": *"[^"]*linux_'"$ARCH"'\.tar\.gz"' | head -1 | cut -d'"' -f4)"
  [[ -n "$asset" ]] || fail "No linux/$ARCH binary asset in engram release $version"
  info "Downloading engram $version (linux/$ARCH)..."

  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  curl -fsSL "$asset" -o "$tmp/engram.tar.gz" || fail "Download of $asset failed"
  tar -xzf "$tmp/engram.tar.gz" -C "$tmp" || fail "Could not extract $asset"
  [[ -f "$tmp/engram" ]] || fail "Archive did not contain an 'engram' binary"
  mkdir -p "$BIN_DIR"
  install -m 0755 "$tmp/engram" "$BIN_DIR/engram"
  "$BIN_DIR/engram" --version >/dev/null 2>&1 || fail "Installed engram binary does not run"
  ENGRAM_BIN="$BIN_DIR/engram"
  ok "engram installed: $("$BIN_DIR/engram" --version 2>/dev/null | head -1) ($BIN_DIR/engram)"
}

# --- 3. OpenCode V2 (system — OPT-IN compatibility line) --------------------
# OpenCode V1 is the default NeoGaeshi line; V2 only installs with --with-v2
# (or is left alone if the user already runs OpenCode 2.x).
install_opencode_v2() {
  printf '\n%sOpenCode V2%s (optional compatibility line)\n' "$VIOLET" "$RESET"

  local cur=""
  if command -v opencode >/dev/null 2>&1; then
    cur="$(opencode --version 2>/dev/null || true)"
    cur="${cur#opencode }"  # `opencode --version` may print "opencode v2.0.32"
  fi
  if [[ "$cur" == v2.* ]]; then
    ok "OpenCode $cur already present, skipping"
    return
  fi
  if [[ "${NEOGAESHI_SKIP_OPENCODE:-0}" == "1" ]]; then
    warn "NEOGAESHI_SKIP_OPENCODE=1 set; skipping OpenCode V2 install (neogaeshi v2 needs it on PATH)"
    return
  fi
  if [[ "$WITH_V2" != "1" ]]; then
    info "OpenCode V2 not installed — the V1 line is the default (use --with-v2 to install V2 as well)"
    return
  fi

  # NOTE: https://opencode.ai/install installs OpenCode *1*; OpenCode 2 has its
  # own official installer (verified 2026-10).
  info "Installing OpenCode V2 via the official installer (-> ~/.opencode/bin)..."
  curl -fsSL https://opencode.ai/v2/install | bash || fail "The OpenCode V2 installer failed. Check your network, or install manually: curl -fsSL https://opencode.ai/v2/install | bash"

  cur=""
  if command -v opencode >/dev/null 2>&1; then
    cur="$(opencode --version 2>/dev/null || true)"
    cur="${cur#opencode }"
  fi
  if [[ "$cur" != v2.* ]]; then
    fail "opencode V2 not runnable after install (reported: '${cur:-not found}'). Open a new shell so ~/.opencode/bin is on PATH, then re-run."
  fi
  ok "OpenCode V2 ready: $cur"
  case ":$PATH:" in
    *":$HOME/.opencode/bin:"*) : ;;
    *) info "NOTE: add ~/.opencode/bin to your PATH (the installer usually wires this into your shell rc)" ;;
  esac
}

# --- 4. OpenCode V1 runtime (isolated) --------------------------------------
install_v1_runtime() {
  printf '\n%s[2/4]%s OpenCode V1 %s (isolated runtime)\n' "$VIOLET" "$RESET" "$V1_VERSION"

  local v1_bin="$V1_PREFIX/node_modules/.bin/opencode"
  if [[ -x "$v1_bin" ]] && [[ "$("$v1_bin" --version 2>/dev/null || true)" == 1.* ]]; then
    ok "OpenCode V1 runtime already present ($("$v1_bin" --version 2>/dev/null)), skipping install"
    return
  fi
  if [[ "${NEOGAESHI_SKIP_RUNTIME:-0}" == "1" ]]; then
    warn "NEOGAESHI_SKIP_RUNTIME=1 set; skipping the V1 runtime install"
    return
  fi

  info "npm install --prefix $V1_PREFIX opencode-ai@$V1_VERSION"
  local attempt
  for attempt in 1 2; do
    if npm install --prefix "$V1_PREFIX" "opencode-ai@$V1_VERSION" >/dev/null 2>&1; then
      break
    fi
    if [[ "$attempt" == "2" ]]; then
      fail "npm install of opencode-ai@$V1_VERSION failed twice. Check your network/npm."
    fi
    info "npm install flaked (libc-detection), retrying once..."
  done
  [[ -x "$v1_bin" ]] || fail "V1 binary missing at $v1_bin after install"
  local ver
  ver="$("$v1_bin" --version 2>/dev/null || true)"
  [[ "$ver" == 1.* ]] || fail "Installed runtime reports '$ver', expected 1.x"
  ok "OpenCode V1 runtime ready: version $ver"
}

# --- 5. NeoGaeshi repo copy -------------------------------------------------
acquire_source() {
  printf '\n%s[3/4]%s NeoGaeshi profile\n' "$VIOLET" "$RESET"

  if [[ -f "$NEOGAESHI_ROOT/v1/bin/neogaeshi" ]]; then
    ok "NeoGaeshi already installed at $NEOGAESHI_ROOT (reusing; delete it to force a fresh copy)"
    return
  fi

  mkdir -p "$NEOGAESHI_ROOT"
  if [[ -n "${NEOGAESHI_SOURCE:-}" ]]; then
    [[ -d "$NEOGAESHI_SOURCE" ]] || fail "NEOGAESHI_SOURCE=$NEOGAESHI_SOURCE is not a directory"
    info "Copying from local source $NEOGAESHI_SOURCE"
    (cd "$NEOGAESHI_SOURCE" && tar --exclude=.git --exclude=workspace --exclude=journal -cf - .) \
      | (cd "$NEOGAESHI_ROOT" && tar -xf -)
  else
    info "Cloning $REPO_URL -> $NEOGAESHI_ROOT"
    git clone --depth 1 "$REPO_URL" "$NEOGAESHI_ROOT" \
      || fail "git clone failed. For pre-release testing, set NEOGAESHI_SOURCE=<local checkout>."
  fi
  [[ -f "$NEOGAESHI_ROOT/v1/bin/neogaeshi" ]] || fail "Repository copy looks incomplete (missing v1/bin/neogaeshi)"
  ok "NeoGaeshi profile in place at $NEOGAESHI_ROOT"
}

# --- 6. Profile config + CLI ------------------------------------------------
install_profile() {
  # Substitute the engram binary path into the V2 profile config at the repo
  # root (the committed file carries an __ENGRAM_BIN__ placeholder).
  sed -i "s|__ENGRAM_BIN__|$ENGRAM_BIN|g" "$NEOGAESHI_ROOT/opencode.json"
  if grep -q "__ENGRAM_BIN__" "$NEOGAESHI_ROOT/opencode.json"; then
    fail "Placeholder substitution failed in $NEOGAESHI_ROOT/opencode.json"
  fi

  # v1/install.sh: hermetic V1 profile (substitutes __NEOGAESHI_ROOT__,
  # __ENGRAM_BIN__, __NEOGAESHI_CONFIG__), runtime if still missing, CLI symlink.
  local extra=()
  if [[ "$WITH_AUTH" == "1" ]]; then extra+=(--with-auth); fi
  if [[ "$FORCE" == "1" ]]; then extra+=(--force); fi
  export NEOGAESHI_ROOT ENGRAM_BIN
  # v1/install.sh checks for a shadowing 'neogaeshi' against the USER's shell
  # PATH — this process's PATH has $BIN_DIR prepended, which would mask it.
  export NEOGAESHI_USER_PATH="$ORIGINAL_PATH"
  bash "$NEOGAESHI_ROOT/v1/install.sh" "${extra[@]+"${extra[@]}"}"
}

# --- 7. Uninstall -----------------------------------------------------------
uninstall() {
  printf '\n%sNeoGaeshi uninstaller%s\n\n' "$VIOLET" "$RESET"

  local cli="$BIN_DIR/neogaeshi"
  if [[ -L "$cli" ]] && [[ "$(readlink "$cli")" == "$NEOGAESHI_ROOT/v1/bin/neogaeshi" ]]; then
    rm "$cli"; ok "Removed $cli"
  else
    info "No NeoGaeshi symlink at $cli (nothing to remove)"
  fi

  if [[ -d "$CONFIG_ROOT" ]]; then
    rm -rf "$CONFIG_ROOT"; ok "Removed V1 profile config ($CONFIG_ROOT)"
  fi
  if [[ -d "$V1_PREFIX" ]]; then
    rm -rf "$V1_PREFIX"; ok "Removed isolated V1 runtime ($V1_PREFIX)"
  fi
  if [[ -f "$NEOGAESHI_ROOT/v1/bin/neogaeshi" ]]; then
    rm -rf "$NEOGAESHI_ROOT"; ok "Removed NeoGaeshi copy ($NEOGAESHI_ROOT)"
  fi

  printf '\n%sNote:%s engram and any system OpenCode V2 binary were left in place\n  (general-purpose tools; remove them yourself if unwanted).\n  Your global opencode config/data (~/.config/opencode, ~/.local/share/opencode)\n  was never touched.\n\n' "$MUTED" "$RESET"
}

# --- 7b. Update mode (run by `neogaeshi update`) ----------------------------
# Fast-forwards the repo copy from origin and re-syncs the hermetic V1 config.
# The placeholder substitution is delegated to v1/install.sh (--update-config)
# so install and update cannot drift apart. Scope: profile only — the V1
# runtime (~/.local/share/opencode-v1), engram, and the user's global opencode
# config/data are separate concerns and are never touched here.
run_update() {
  local line="$1"   # v1 | v2
  printf '\n%sNeoGaeshi update%s (%s line)\n\n' "$VIOLET" "$RESET" "$line"

  [[ -f "$NEOGAESHI_ROOT/v1/bin/neogaeshi" ]] \
    || fail "No NeoGaeshi install found at $NEOGAESHI_ROOT. Install first: curl -fsSL $REPO_URL/raw/main/install.sh | bash"

  git -C "$NEOGAESHI_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || fail "The install at $NEOGAESHI_ROOT is not a git clone (it was installed from a local source copy), so 'neogaeshi update' cannot update it automatically.
Manual remedy: refresh the repo copy from a fresh clone, then re-run the installer:
  rm -rf $NEOGAESHI_ROOT
  git clone $REPO_URL $NEOGAESHI_ROOT
  bash $NEOGAESHI_ROOT/install.sh"

  local branch
  branch="$(git -C "$NEOGAESHI_ROOT" symbolic-ref --short HEAD 2>/dev/null || true)"
  [[ -n "$branch" ]] \
    || fail "The checkout at $NEOGAESHI_ROOT is in detached-HEAD state; cannot update a branch. Re-install NeoGaeshi to get a clean checkout."

  # Resolve engram once: needed for the V1 re-sync and to recognize the
  # installer's own edit of the tracked root opencode.json (see below).
  local engram_bin="${ENGRAM_BIN:-$(command -v engram || true)}"

  # Refuse to run over user edits. Two kinds of dirt are recognized as
  # installer noise, not user work:
  #   - mode-only changes (install.sh chmod +x's the launcher in the checkout)
  #   - the installer's in-place __ENGRAM_BIN__ rewrite of the tracked root
  #     opencode.json (for the V2 line); reverted before the merge, re-applied
  #     after it
  local subst_applied=0
  if [[ -n "$(git -C "$NEOGAESHI_ROOT" status --porcelain -- opencode.json)" ]] \
    && [[ -n "$engram_bin" ]] \
    && cmp -s <(sed "s|$engram_bin|__ENGRAM_BIN__|g" "$NEOGAESHI_ROOT/opencode.json") \
              <(git -C "$NEOGAESHI_ROOT" show HEAD:opencode.json); then
    subst_applied=1
  fi

  # Any other content change, staged change, or untracked file is user work.
  # numstat lists mode-only changes as "0<TAB>0<TAB>path" — no content change,
  # so they (and only they) are filtered out as installer noise.
  local leftovers=""
  leftovers="$(git -C "$NEOGAESHI_ROOT" diff --numstat | grep -v $'^0\t0\t' || true)"
  if [[ "$subst_applied" == "1" ]]; then
    leftovers="$(printf '%s\n' "$leftovers" | grep -v $'\topencode.json$' || true)"
  fi
  leftovers+="$(git -C "$NEOGAESHI_ROOT" diff --cached --numstat)"
  leftovers+="$(git -C "$NEOGAESHI_ROOT" ls-files --others --exclude-standard)"
  if [[ -n "${leftovers//[[:space:]]/}" ]]; then
    fail "The checkout at $NEOGAESHI_ROOT has local modifications; refusing to update over them.
Inspect with:  git -C $NEOGAESHI_ROOT status
Commit or stash your changes there, then re-run 'neogaeshi update'."
  fi

  # Absorb the mode-only worktree noise before the merge: git refuses to
  # merge over ANY local difference, including a bare chmod +x. Restoring the
  # index's mode is safe here (content is identical) and the merge then
  # re-applies the upstream mode.
  local mode_only f
  mode_only="$(git -C "$NEOGAESHI_ROOT" diff --numstat | grep $'^0\t0\t' | cut -f3- || true)"
  if [[ -n "$mode_only" ]]; then
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      git -C "$NEOGAESHI_ROOT" checkout -- "$f"
    done <<<"$mode_only"
    info "Absorbed installer mode-only changes (chmod +x on files in the checkout)"
  fi

  if [[ "$subst_applied" == "1" ]]; then
    git -C "$NEOGAESHI_ROOT" checkout -- opencode.json
    info "Recognized the installer's own __ENGRAM_BIN__ edit of opencode.json (not user work); re-applied after the update"
  fi

  local old_sha new_sha
  old_sha="$(git -C "$NEOGAESHI_ROOT" rev-parse HEAD)"
  info "Fetching origin $branch..."
  git -C "$NEOGAESHI_ROOT" fetch --quiet origin "$branch" \
    || fail "git fetch from origin failed (network?). Nothing was changed."

  if ! git -C "$NEOGAESHI_ROOT" merge-base --is-ancestor HEAD "origin/$branch"; then
    fail "The checkout at $NEOGAESHI_ROOT has local commits that are not on origin/$branch (it diverged).
Refusing to reset or overwrite local work. Inspect with:
  git -C $NEOGAESHI_ROOT log --oneline origin/$branch..HEAD"
  fi

  new_sha="$(git -C "$NEOGAESHI_ROOT" rev-parse "origin/$branch")"
  if [[ "$old_sha" == "$new_sha" ]]; then
    ok "Already up to date (origin/$branch @ ${new_sha:0:7})"
  else
    git -C "$NEOGAESHI_ROOT" merge --ff-only --quiet "origin/$branch" \
      || fail "Fast-forward merge failed; nothing beyond the fetch was changed."
    ok "Updated to $(git -C "$NEOGAESHI_ROOT" rev-parse --short HEAD)"
    printf '\n%sPulled commits:%s\n' "$MUTED" "$RESET"
    git -C "$NEOGAESHI_ROOT" log --oneline "$old_sha..$new_sha" | sed 's/^/  /'
    info "Profile, skills and launcher updated"
  fi

  # Re-apply the installer's __ENGRAM_BIN__ edit if we reverted it above, so
  # the tree ends in the same installed state it was in before the update.
  if [[ "$subst_applied" == "1" ]]; then
    sed -i "s|__ENGRAM_BIN__|$engram_bin|g" "$NEOGAESHI_ROOT/opencode.json"
  fi

  if [[ "$line" == "v2" ]]; then
    printf '\n%sThe V2 profile IS the repo checkout:%s it updated in place at\n  %s\nRestart the V2 line from the repo root to pick up the changes: %sneogaeshi v2%s\n\n' \
      "$MUTED" "$RESET" "$NEOGAESHI_ROOT" "$BOLD" "$RESET"
    return 0
  fi

  # V1 line: re-sync the hermetic config from the repo's templates (with
  # backups of any local edits) via the same code path as a fresh install.
  printf '\n'
  info "Re-syncing the hermetic V1 profile config..."
  [[ -n "$engram_bin" ]] \
    || fail "engram not found on PATH (needed to re-sync the V1 config). Install engram, or set ENGRAM_BIN, then re-run."
  ENGRAM_BIN="$engram_bin" bash "$NEOGAESHI_ROOT/v1/install.sh" --update-config

  printf '\n%sDone.%s The OpenCode V1 runtime (~/.local/share/opencode-v1) and engram\nare separate components and were not touched — runtime updates are a\nseparate concern from profile updates.\n\n' "$VIOLET" "$RESET"
}

# --- 8. Sanity + next steps -------------------------------------------------
# Resolve a command the way a shell whose PATH is $1 would: first file match
# wins. Used to prove WHICH 'neogaeshi' a sanity check (or a shadow check)
# actually probed; runs in a contained subshell so $PATH never changes here.
resolve_on_path() {
  ( PATH="$1"; command -v "$2" 2>/dev/null || true )
}

finish() {
  printf '\n%s[4/4]%s Sanity check\n' "$VIOLET" "$RESET"
  # `|| true` + empty-check instead of `|| echo`: `head -1` closes the pipe
  # early, so a multi-line --version can die of SIGPIPE under `pipefail`
  # even when it ran fine.
  local v_engram v_ng v_oc
  v_engram="$(engram --version 2>/dev/null | head -1 || true)"
  # Sanity evidence must name the copy it probed: run the 'neogaeshi' the
  # USER's shell resolves (a stale copy earlier on PATH outranks our symlink
  # there), not the one this process sees — this process prepends $BIN_DIR to
  # PATH, which would mask the shadow. resolve_on_path is a deliberate,
  # minimal duplicate of the resolve in v1/install.sh: that script runs in a
  # subshell, so it cannot export its verdict back here.
  local ng_run ng_via=""
  ng_run="$(resolve_on_path "$ORIGINAL_PATH" neogaeshi)"
  [[ "$ng_run" == /* ]] || ng_run=""
  # Fallback: ~/.local/bin not on the user's PATH yet -> probe the installer's.
  [[ -n "$ng_run" ]] || ng_run="$(command -v neogaeshi 2>/dev/null || true)"
  if [[ -n "$ng_run" ]] \
     && [[ "$(readlink -f "$ng_run" 2>/dev/null || true)" != "$(readlink -f "$NEOGAESHI_ROOT/v1/bin/neogaeshi" 2>/dev/null || true)" ]]; then
    ng_via="$(printf ' (via %s — shadows the installed launcher; see the WARNING above)' "$ng_run")"
  fi
  if [[ -n "$ng_run" ]]; then
    v_ng="$("$ng_run" --version 2>/dev/null | head -1 || true)"
  fi
  v_oc="$(opencode --version 2>/dev/null | head -1 || true)"
  v_oc="${v_oc#opencode }"
  [[ -n "$v_engram" ]] || v_engram="NOT RUNNABLE"
  [[ -n "$v_ng" ]] || v_ng="NOT RUNNABLE"
  [[ -n "$v_oc" ]] || v_oc="NOT RUNNABLE"
  printf '  engram      %s\n' "$v_engram"
  printf '  neogaeshi   %s%s\n' "$v_ng" "$ng_via"
  printf '  opencode v2 %s\n' "$v_oc"

  # PATH advice comes from v1/install.sh, which checks it against the user's
  # own PATH ($ORIGINAL_PATH). Checking the installer's PATH here could never
  # fire: it always starts with $BIN_DIR by construction.

  # The V2 line is opt-in: only point at it when OpenCode V2 is actually present.
  local v2_note
  if [[ "$v_oc" == v2.* ]]; then
    v2_note="$(printf '  3. Optional V2 line: %sneogaeshi v2%s  (system OpenCode V2 from the profile root)' "$BOLD" "$RESET")"
  else
    v2_note="$(printf '  3. Optional V2 line: %sneogaeshi v2%s needs OpenCode V2 on PATH;\n       get it with: bash %s/install.sh --with-v2  (V1 stays the default)' "$BOLD" "$RESET" "$NEOGAESHI_ROOT")"
  fi

  cat <<EOF

${VIOLET}✔ NeoGaeshi installed.${RESET}

${BOLD}Next steps${RESET}
  1. Connect a model provider (the one manual step):
       neogaeshi auth login        # inside the isolated V1 profile
     or run /connect inside the TUI. Re-run this installer with --with-auth to
     reuse an existing ~/.local/share/opencode/auth.json instead.
  2. Start the product (V1 line): ${BOLD}neogaeshi${RESET}   (TUI with home logo, hermetic)
     Continue a session:          ${BOLD}neogaeshi -c${RESET}   Resume by id: ${BOLD}neogaeshi -s <id>${RESET}
${v2_note}

${MUTED}Inside the TUI: /neogaeshi-triage /neogaeshi-hunt /neogaeshi-timeline
/neogaeshi-detection /neogaeshi-status — 39 curated defensive skills + engram memory.${RESET}

EOF
}

# --- Run --------------------------------------------------------------------
if [[ "$UNINSTALL" == "1" ]]; then
  uninstall
  exit 0
fi

if [[ "$UPDATE" == "1" ]]; then
  run_update v1
  exit 0
fi
if [[ "$UPDATE_V2" == "1" ]]; then
  run_update v2
  exit 0
fi

preflight
install_engram
install_opencode_v2
install_v1_runtime
acquire_source
install_profile
finish
