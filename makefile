makefile := $(abspath $(lastword $(MAKEFILE_LIST)))
dotfiles := $(abspath $(dir $(makefile)))
~ := $(abspath $(dotfiles)/~)

mkdir := mkdir -p
ln := ln -snf

# Generates a command to create the specified directory.
# Generates the empty string if the directory has already been created.
# Assumes user's home directory has already been created.
created_directories := $(HOME)
define make_directory_once
$(if $(findstring $(1),$(created_directories)),,$(eval created_directories += $(1))$(mkdir) $(1))
endef

ensure_directory_exists = $(call make_directory_once,$(abspath $(dir $(1))))

link = $(ln) $(1) $(2)

force:
~/% : $(~)/% force
	$(call ensure_directory_exists,$@)
	$(call link,$<,$@)

to_home_directory = $(patsubst $(~)/%,$(HOME)/%,$(1))

user_binaries := $(call to_home_directory,$(wildcard $(~)/bin/*))
all += bin
bin : $(user_binaries)

all += bash
bash : ~/.bash_profile ~/.bashrc

all += git
git : ~/.gitconfig

all += vim
vim : ~/.vimrc

sublime_text_3_user_preferences := $(call to_home_directory,$(wildcard $(~)/.config/sublime-text-3/Packages/User/*.sublime-settings))
all += sublime-text-3
sublime-text-3 : $(sublime_text_3_user_preferences)

.Xresources.d := $(call to_home_directory,$(wildcard $(~)/.Xresources.d/*))
all += Xresources
Xresources: ~/.Xresources $(.Xresources.d)

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
