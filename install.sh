#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC="$HOME/.bashrc"
BIN_DIR="$HOME/.local/bin"

FORCE_BIND=0
for arg in "$@"; do
    case "$arg" in
        --overwrite-bind) FORCE_BIND=1 ;;
        *)
            echo "error: unknown argument: $arg" >&2
            echo "usage: $0 [--overwrite-bind]" >&2
            exit 1
            ;;
    esac
done

if [ ! -f "$SCRIPT_DIR/yk" ] || [ ! -f "$SCRIPT_DIR/yk-keybind.bashrc" ]; then
    echo "error: expected to find 'yk' and 'yk-keybind.bashrc' next to this script (in $SCRIPT_DIR)" >&2
    exit 1
fi

# Checks $BASHRC for $1, and on a match prints the matching line(s) (with
# line numbers, so you can go look) plus $2 as the description. Aborts
# unless --overwrite-bind was given, in which case it warns and continues.
check_bind() {
    local pattern="$1" description="$2" match
    [ -f "$BASHRC" ] || return 0
    match="$(grep -nF "$pattern" "$BASHRC" || true)"
    [ -n "$match" ] || return 0

    if [ "$FORCE_BIND" -eq 1 ]; then
        echo "warning: $BASHRC already has $description:" >&2
        echo "$match" | sed 's/^/  /' >&2
        echo "  --overwrite-bind given, continuing anyway." >&2
    else
        echo "error: $BASHRC already has $description:" >&2
        echo "$match" | sed 's/^/  /' >&2
        echo "Remove or rename it first, then re-run this installer," >&2
        echo "or pass --overwrite-bind to install anyway (may result in duplicate/conflicting binds)." >&2
        exit 1
    fi
}

echo "==> Checking for an existing Ctrl+F3 bind in $BASHRC"
check_bind '\e[1;5R' 'a Ctrl+F3 bind (xterm/libvte form "\e[1;5R")'
check_bind '\e[13;5~' 'a Ctrl+F3 bind (Kitty keyboard protocol form "\e[13;5~")'
check_bind 'yk_bind' 'something matching "yk_bind" (function name collision)'

echo "==> Checking dependencies"
missing=()
for cmd in ykman pkcs11-tool pinentry-gnome3 fzf pkill python3; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
pexpect_missing=0
if command -v python3 >/dev/null 2>&1 && ! python3 -c 'import pexpect' >/dev/null 2>&1; then
    pexpect_missing=1
fi
if [ "${#missing[@]}" -gt 0 ] || [ "$pexpect_missing" -eq 1 ]; then
    [ "${#missing[@]}" -gt 0 ] && echo "warning: missing commands: ${missing[*]}" >&2
    [ "$pexpect_missing" -eq 1 ] && echo "warning: python3-pexpect not importable" >&2
    echo "  sudo apt install python3-pexpect yubikey-manager openssh-client opensc \\" >&2
    echo "      pinentry-gnome3 fzf psmisc" >&2
fi

echo "==> Checking pcscd"
if command -v systemctl >/dev/null 2>&1 && ! systemctl is-active --quiet pcscd 2>/dev/null; then
    echo "warning: pcscd is not active - yk needs it for PC/SC access to the YubiKey's PIV applet." >&2
    echo "  sudo systemctl enable --now pcscd" >&2
fi

echo "==> Installing yk to $BIN_DIR"
mkdir -p "$BIN_DIR"
if [ -f "$BIN_DIR/yk" ] && cmp -s "$SCRIPT_DIR/yk" "$BIN_DIR/yk"; then
    echo "  $BIN_DIR/yk already up to date, skipping"
elif [ -f "$BIN_DIR/yk" ]; then
    echo "  $BIN_DIR/yk already exists and differs from this repo's version."
    read -r -p "  Overwrite? [y/N] " reply || reply="n"
    case "$reply" in
        [yY]|[yY][eE][sS])
            cp "$SCRIPT_DIR/yk" "$BIN_DIR/yk"
            chmod +x "$BIN_DIR/yk"
            echo "  overwritten"
            ;;
        *)
            echo "  leaving existing $BIN_DIR/yk in place" >&2
            ;;
    esac
else
    cp "$SCRIPT_DIR/yk" "$BIN_DIR/yk"
    chmod +x "$BIN_DIR/yk"
    echo "  installed"
fi

echo "==> Backing up $BASHRC"
if [ -f "$BASHRC" ]; then
    cp "$BASHRC" "$BASHRC.bak-$(date +%Y%m%d%H%M%S)"
else
    touch "$BASHRC"
fi

echo "==> Checking \$PATH for $BIN_DIR"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]] && ! grep -qF '.local/bin' "$BASHRC"; then
    echo "  adding $BIN_DIR to PATH in $BASHRC"
    {
        echo ''
        echo '# Added by yk install.sh'
        echo 'if [ -d "$HOME/.local/bin" ] ; then'
        echo '    PATH="$HOME/.local/bin:$PATH"'
        echo 'fi'
    } >> "$BASHRC"
fi

echo "==> Appending the Ctrl+F3 keybind to $BASHRC"
echo '' >> "$BASHRC"
cat "$SCRIPT_DIR/yk-keybind.bashrc" >> "$BASHRC"

echo
echo "Done. Open a new shell (or run: source ~/.bashrc) and press Ctrl+F3 to test."
