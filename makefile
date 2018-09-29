makefile := $(abspath $(lastword $(MAKEFILE_LIST)))
dotfiles := $(abspath $(dir $(makefile)))
~ := $(abspath $(dotfiles)/~)

mkdir := mkdir -p
ln := ln -snf

# x - y = 0 ∴ x = y
equal? = $(if $(subst $(1),,$(2)),,equal)
not_equal? = $(if $(call equal?,$(1),$(2)),,not_equal)

# Generates a command to create the specified directory.
# User's home directory can be assumed to always exist,
# so the function evaluates to the empty string in that case.
make_directory_unless_home = $(if $(call not_equal?,$(abspath $(1)),$(abspath $(HOME))),$(mkdir) $(1),) 
ensure_directory_exists = $(call make_directory_unless_home,$(dir $(1)))

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
bash : ~/.bashrc

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
i3 : ~/.config/i3/config

all : $(all)

.PHONY: all $(all)
