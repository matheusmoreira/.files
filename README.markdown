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

## virtdev tmux status forwarding

Forwards shell status (directory, git info, exit codes) from virtdev
guest VMs to the host's tmux status bar via a reverse-forwarded Unix
socket.

```sh
make bash     # symlinks .bashrc + libraries (import, terminal, prompt)
make virtdev  # symlinks triggers, listener, systemd unit, tmpfiles, manifests
systemctl --user daemon-reload
```

### Guest provisioning

Guests need `/tmp/virtdev/socket/` to exist before SSH connects
(the `RemoteForward` socket binding happens at connection time,
before the shell starts). Add to each project's provision script:

```sh
# /etc/tmpfiles.d/virtdev-tmux-status.conf — survives reboots
sudo tee /etc/tmpfiles.d/virtdev-tmux-status.conf <<< 'd /tmp/virtdev/socket 0700 dev dev -'
sudo systemd-tmpfiles --create

# also install socat if not already present
sudo pacman -S --noconfirm --needed socat
```

### Known limitation: systemd ignores symlinked tmpfiles.d

`systemd-tmpfiles --user` does not discover configs that are symlinks
in `~/.config/tmpfiles.d/`. The `make virtdev` target still deploys
the symlink (it works when the path is given explicitly), but the
host does not rely on it — the pre-ssh trigger creates the host
socket directory via `mkdir -p` directly.

## Git workflow scripts

In `~/.local/bin/`:

- `git review [-N] [upstream]` — interactive review (default: all commits since upstream).
- `git peek [-N]` — show pending review/ship without acting.
- `git ship [-N]` — push the next N commits (default: 1).
- `git next` — accept current review commit, advance, show the next.
