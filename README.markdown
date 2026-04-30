# Dotfiles

My Arch Linux environment, installed by symlink via GNU Make.

## Layout

- `~/` — user files, mirrors `$HOME`
- `etc/` — system config, mirrors `/etc`
- `root/` — scripts run as root

## Install

```sh
make basic                  # bash, git, ssh, vim, nano
make sway kitty mpv claude  # per-tool installs
sudo make arch-linux        # rsync etc/ over /etc, --existing only
make lint                   # shellcheck on ~/.local/bin and root/
```

`make` with no target runs `basic`.

## Wayland session (sway + systemd via uwsm)

```sh
sudo pacman -S uwsm
make sway
systemctl --user daemon-reload
systemctl --user enable swayidle.service
uwsm start sway             # not just `sway`
```

`make sway` symlinks the sway, swaylock, and swayidle configs into place.
`~/.config/sway/config` exec's `uwsm finalize`, which activates
`graphical-session.target` and pulls in `swayidle.service` automatically.

Verify:

```sh
systemctl --user status swayidle
journalctl --user -u swayidle -f
```

## Git workflow scripts

In `~/.local/bin/`:

- `git review [-N] [upstream]` — interactive review (default: all commits since upstream).
- `git peek [-N]` — show pending review/ship without acting.
- `git ship [-N]` — push the next N commits (default: 1).
- `git next` — accept current review commit, advance, show the next.
