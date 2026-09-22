# Append this to ~/.bashrc (or source it from there).
#
# Ctrl+F3: add a YubiKey PIV identity to the ssh-agent (fzf picker if
# multiple keys are connected; j/k or arrows to move, Enter to select).
# yk --shell prints status to stderr and only "export SSH_AUTH_SOCK=..."
# to stdout (it points at a fresh, per-key dedicated agent each time) -
# a bare "yk" call can't mutate this shell's environment as a
# subprocess, so this has to be eval'd.
yk_bind() {
    eval "$(yk --shell)"
}
# Two bindings for two different F3 encodings: older xterm/libvte
# terminals (GNOME Terminal, Console) send the SS3-letter form
# "\e[1;5R"; terminals implementing the Kitty keyboard protocol's
# legacy-compatible alternate form (Ghostty, kitty) send "\e[13;5~"
# instead - a different VT220-style numbering (F1=11 F2=12 F3=13 F4=14),
# not a typo of the first form. If Ctrl+F3 doesn't fire in your
# terminal, run `cat -v` and press it to see which sequence it actually
# sends, and add a third bind -x line for that sequence.
bind -x '"\e[1;5R": yk_bind'   # Ctrl+F3 (xterm/libvte)
bind -x '"\e[13;5~": yk_bind'  # Ctrl+F3 (Kitty keyboard protocol)
