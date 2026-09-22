#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHRC="$HOME/.bashrc"
BIN_DIR="$HOME/.local/bin"

if [ ! -f "$SCRIPT_DIR/yk" ] || [ ! -f "$SCRIPT_DIR/yk-keybind.bashrc" ]; then
    echo "error: expected to find 'yk' and 'yk-keybind.bashrc' next to this script (in $SCRIPT_DIR)" >&2
    exit 1
fi

echo "==> Checking for an existing Ctrl+F3 bind in $BASHRC"
if [ -f "$BASHRC" ] && grep -qF '\e[1;5R' "$BASHRC"; then
    echo "error: $BASHRC already binds \"\\e[1;5R\" (Ctrl+F3, xterm/libvte form) to something." >&2
    echo "Remove or rename that binding first, then re-run this installer." >&2
    exit 1
fi
if [ -f "$BASHRC" ] && grep -qF '\e[13;5~' "$BASHRC"; then
    echo "error: $BASHRC already binds \"\\e[13;5~\" (Ctrl+F3, Kitty keyboard protocol form) to something." >&2
    echo "Remove or rename that binding first, then re-run this installer." >&2
    exit 1
fi
if [ -f "$BASHRC" ] && grep -qF 'yk_bind' "$BASHRC"; then
    echo "error: $BASHRC already has something matching \"yk_bind\" (function name collision)." >&2
    echo "Remove or rename it first, then re-run this installer." >&2
    exit 1
fi

echo "==> Checking dependencies"
missing=()
for cmd in ykman pkcs11-tool pinentry-gnome3 fzf pkill secret-tool python3; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "warning: missing commands: ${missing[*]}" >&2
    echo "  sudo apt install python3-pexpect yubikey-manager openssh-client opensc \\" >&2
    echo "      libsecret-tools pinentry-gnome3 fzf psmisc" >&2
fi
if command -v python3 >/dev/null 2>&1 && ! python3 -c 'import pexpect' >/dev/null 2>&1; then
    echo "warning: python3-pexpect not importable - install it (see the apt command above)." >&2
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
cat "$SCRIPT_DIR/yk-keybind.bashrc" >> "$BASHRC"

echo
echo "Done. Open a new shell (or run: source ~/.bashrc) and press Ctrl+F3 to test."
echo
echo "Optional: cache a PIN so you're not prompted every time for a specific key:"
echo '  secret-tool store --label="YubiKey <serial> PIV PIN" \'
echo '      application yk-piv-agent yubikey-serial <serial>'
