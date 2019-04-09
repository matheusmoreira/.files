makefile := $(abspath $(lastword $(MAKEFILE_LIST)))
dotfiles := $(abspath $(dir $(makefile)))
~ := $(abspath $(dotfiles)/~)

mkdir := mkdir -p
ln := ln -snf

# Determines whether the given path exists and is a directory.
# Only existing directories contain a "." entry.
directory? = $(wildcard $(1)/.)

# Generates a command that creates the given directory.
# Generates the empty string if the directory already exists.
ensure_directory_exists = $(if $(call directory?,$(1)),,$(mkdir) $(1))

link = $(ln) $(1) $(2)

force:
~/% : $(~)/% force
	$(call ensure_directory_exists,$(@D))
	$(call link,$<,$@)

to_home_directory = $(patsubst $(~)/%,$(HOME)/%,$(1))

# Phony targets

user_binaries := $(call to_home_directory,$(wildcard $(~)/bin/*))
all += bin
bin : $(user_binaries)

all += bash
bash : ~/.bash_profile ~/.bashrc

all += git
git : ~/.gitconfig

all += vim
vim : ~/.vimrc

all += gpg
gpg : ~/.gnupg/gpg.conf ~/.gnupg/dirmngr.conf

sublime_text_3_user_preferences := $(call to_home_directory,$(wildcard $(~)/.config/sublime-text-3/Packages/User/*.sublime-settings))
all += sublime-text-3
sublime-text-3 : $(sublime_text_3_user_preferences)

.Xresources.d := $(call to_home_directory,$(wildcard $(~)/.Xresources.d/*))
all += Xresources
Xresources: ~/.Xresources $(.Xresources.d)

all += xinitrc
xinitrc : ~/.xinitrc

all += X
X : Xresources xinitrc

all += urxvt
urxvt : Xresources

kitty_conf := $(call to_home_directory,$(wildcard $(~)/.config/kitty/*.conf))
kitty_themes := $(call to_home_directory,$(wildcard $(~)/.config/kitty/themes/*.conf))
all += kitty
kitty : $(kitty_conf) $(kitty_themes)

all += i3
i3 : ~/.config/i3/config ~/.config/i3status/config

all += mpv
mpv : ~/.config/mpv/mpv.conf

all : $(all)

.PHONY: all $(all)
.DEFAULT_GOAL := all
