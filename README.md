# yk

A `bind -x` keybind for bash that adds a YubiKey PIV identity to `ssh-agent`
mid-command, without ever risking a PIN attempt landing on the wrong key.

## The problem this fixes

`ssh-add -s <opensc-pkcs11.so>` sends the one PIN you type to *every* PIV
token the module currently sees. With two YubiKeys connected and different
PINs, that silently burns a PIN retry attempt on whichever one you didn't
mean to touch (`ssh-pkcs11.c`'s `pkcs11_register_provider()` loops every
slot and calls `C_Login` with the same PIN in each). Three wrong attempts
locks a YubiKey's PIV PIN and forces a PUK recovery.

`yk` scopes every add to exactly one physical key:

- A dedicated `ssh-agent` per YubiKey serial (`/run/user/<uid>/yk-agent-<serial>.sock`),
  killed and restarted fresh on every use.
- Before starting it, an `OPENSC_CONF` override is generated that hides
  every *other* currently-connected reader via OpenSC's `ignored_readers`
  directive, and self-verifies (re-lists slots through it) before it's
  ever trusted with a real PIN. That config is baked into the new agent's
  own environment at spawn time - not toggled around individual `ssh-add`
  calls, which has no effect (`ssh-add` only talks to the already-running
  agent over a socket, it doesn't share environment with it; only the
  process that calls `C_Initialize()` reads `OPENSC_CONF`, which for
  `ssh-agent` is the `ssh-pkcs11-helper` child it forks, inheriting
  `ssh-agent`'s environment from spawn, not anything set later).

A fresh dedicated agent means re-entering the PIN each time - that's the
accepted tradeoff for a tool that's invoked deliberately (a keybind press),
not on a hot path.

## Install

```
./install.sh
```

Checks dependencies and `pcscd` status (warns with the fix rather than
auto-installing anything), refuses to run if `~/.bashrc` already has a
Ctrl+F3 bind (old or new F3 escape sequence, or a `yk_bind` name
collision) rather than risk double-binding or clobbering an existing
one, backs up `~/.bashrc` before touching it, adds `~/.local/bin` to
`PATH` if it isn't already, and skips the copy silently if
`~/.local/bin/yk` is already identical (prompts before overwriting if
it differs). Then open a new shell, or re-source `~/.bashrc`.

To do it by hand instead:

```
sudo apt install python3-pexpect yubikey-manager openssh-client opensc \
    libsecret-tools pinentry-gnome3 fzf psmisc
sudo systemctl enable --now pcscd

cp yk ~/.local/bin/yk
chmod +x ~/.local/bin/yk

cat yk-keybind.bashrc >> ~/.bashrc
# then open a new shell, or Ctrl+F4-equivalent re-source it
```

Only tested against `opensc-pkcs11.so` at its stock Ubuntu path
(`/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so`, hardcoded as
`PKCS11_PROVIDER` at the top of `yk`) - adjust that constant if yours
lives elsewhere (different architecture, different distro).

## Use

Press Ctrl+F3 (see `yk-keybind.bashrc`) mid-command in any bash shell.
`yk`:

1. Lists connected YubiKeys (`ykman list`).
2. If more than one is connected, shows an `fzf` picker (bound to `j`/`k`
   in addition to arrows) to choose which one; if only one is connected,
   picks it automatically.
3. Starts a dedicated, correctly-scoped `ssh-agent` for that one key.
4. Prompts for the PIN via a GUI `pinentry` popup (so it doesn't fight
   your terminal's readline buffer), unless a PIN is already cached for
   that serial (see below).
5. Adds the identity and points this shell's `SSH_AUTH_SOCK` at the new
   agent - your half-typed command is untouched, since `yk` never writes
   to `READLINE_LINE`.

Flags: `--prompt-pin` forces the interactive prompt even if a PIN is
cached; `--test-pin` just exercises the `pinentry` popup in isolation;
`--shell` (used internally by the keybind) prints only
`export SSH_AUTH_SOCK=...` to stdout, status to stderr.

### Caching a PIN (optional)

To skip the prompt for a specific key, store its PIN in the freedesktop
Secret Service (e.g. gnome-keyring):

```
secret-tool store --label="YubiKey <serial> PIV PIN" \
    application yk-piv-agent yubikey-serial <serial>
```

`<serial>` is the numeric serial `ykman list` shows for that key. `yk`
looks this up (scoped to the one key it's actually adding) before
falling back to the `pinentry` popup.

## Why bash, not a spawned terminal or GUI dialog

`yk` runs `fzf` as a normal foreground subprocess - it reads the
candidate list from stdin and draws its interactive UI to the terminal,
so it works directly inside whatever shell invoked it. No spawned window,
no GTK dialog (`zenity`/`rofi`'s list widgets can't be bound to custom
keys at all; `fzf` can, via `--bind`). This also means `yk` only makes
sense invoked from an interactive shell that already has a real terminal
- it doesn't attempt to work from a display-manager-level global
keybind with no parent shell.

**Implementation note if you adapt `pick_via_fzf`:** capture only
`fzf`'s stdout (where the final selection goes). If you capture stderr
too (e.g. via `subprocess.run(..., capture_output=True)`), you trap the
entire rendered UI in a pipe no one can see - `fzf` runs and responds to
input correctly the whole time, the screen just never shows any of it,
which looks exactly like a hang.
