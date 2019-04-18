makefile := $(abspath $(lastword $(MAKEFILE_LIST)))
dotfiles := $(abspath $(dir $(makefile)))
~ := $(abspath $(dotfiles)/~)

# Converts the list of paths specified in $(3) from paths prefixed by $(1)
# to paths prefixed by $(2).
convert_prefix = $(patsubst $(1)/%,$(2)/%,$(3))

# Converts paths to files in $(HOME) to paths in $(~).
~.to_dotfiles = $(call convert_prefix,$(HOME),$(~),$(1))

# Converts paths to files in $(~) to paths in $(HOME).
~.to_user = $(call convert_prefix,$(~),$(HOME),$(1))

# Converts paths relative to $(HOME) to absolute paths in $(~).
~.user_to_dotfiles = $(call ~.to_dotfiles,$(wildcard $(addprefix $(HOME)/,$(1))))

# Converts paths relative to $(~) to absolute paths in $(HOME).
~.dotfiles_to_user = $(call ~.to_user,$(wildcard $(addprefix $(~)/,$(1))))

# XDG Base Directory Specification
# https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
#
# Files in the repository are stored in the default directories.
# Links in $(HOME) take the XDG variables into account.

# Variable definition template for XDG directories.
define XDG.template
XDG_$(1)_HOME.default := $$(HOME)/$(2)
XDG_$(1)_HOME.dotfiles := $$(call ~.to_dotfiles,$$(XDG_$(1)_HOME.default))
XDG_$(1)_HOME ?= $$(XDG_$(1)_HOME.default)

$(1).to_dotfiles = $$(call convert_prefix,$$(XDG_$(1)_HOME),$$(XDG_$(1)_HOME.dotfiles),$$(1))
$(1).to_user = $$(call convert_prefix,$$(XDG_$(1)_HOME.dotfiles),$$(XDG_$(1)_HOME),$$(1))

$(1).user_to_dotfiles = $$(call $(1).to_dotfiles,$$(wildcard $$(addprefix $$(XDG_$(1)_HOME)/,$$(1))))
$(1).dotfiles_to_user = $$(call $(1).to_user,$$(wildcard $$(addprefix $$(XDG_$(1)_HOME.dotfiles)/,$$(1))))
endef

# Defines XDG variables for the given type and default directory.
XDG.define = $(eval $(call XDG.template,$(1),$(2)))

$(call XDG.define,DATA,.local/share)
$(call XDG.define,CONFIG,.config)

# Commands to use for directory and symbolic link creation.
mkdir := mkdir -p
ln := ln -snf

# Determines whether the given path exists and is a directory.
# Only existing directories contain a "." entry.
directory? = $(wildcard $(1)/.)

# Generates a command that creates the given directory.
# Generates the empty string if the directory already exists.
ensure_directory_exists = $(if $(call directory?,$(1)),,$(mkdir) $(1))

# Generates a command to link $(2) to $(1).
link = $(ln) $(1) $(2)

# Map files in $(~) to $(HOME).
force:
~/% : $(~)/% force
	$(call ensure_directory_exists,$(@D))
	$(call link,$<,$@)

# Phony targets

user_binaries := $(call ~.dotfiles_to_user,bin/*)
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

sublime_text_3_user_preferences := $(call ~.dotfiles_to_user,.config/sublime-text-3/Packages/User/*.sublime-settings)
all += sublime-text-3
sublime-text-3 : $(sublime_text_3_user_preferences)

.Xresources.d := $(call ~.dotfiles_to_user,.Xresources.d/*)
all += Xresources
~/.Xresources : $(.Xresources.d)
Xresources: ~/.Xresources

all += xinitrc
xinitrc : ~/.xinitrc

all += X
X : Xresources xinitrc

all += urxvt
urxvt : Xresources

kitty_conf := $(call ~.dotfiles_to_user,.config/kitty/*.conf)
kitty_themes := $(call ~.dotfiles_to_user,.config/kitty/themes/*.conf)
all += kitty
kitty : $(kitty_conf) $(kitty_themes)

all += i3
i3 : ~/.config/i3/config ~/.config/i3status/config

all += mpv
mpv : ~/.config/mpv/mpv.conf

all : $(all)

.PHONY: all $(all)
.DEFAULT_GOAL := all
