makefile := $(abspath $(lastword $(MAKEFILE_LIST)))
dotfiles := $(abspath $(dir $(makefile)))
~ := $(abspath $(dotfiles)/~)

# Converts the list of paths specified in $(3) from paths prefixed by $(1)
# to paths prefixed by $(2).
convert_prefix = $(patsubst $(1)/%,$(2)/%,$(3))

# Convert a list of paths to files in the user's home directory to paths in $(~).
# All arguments are relative to the user's home directory directory.
to_dotfiles_home = $(call convert_prefix,$(HOME),$(~),$(wildcard $(addprefix $(HOME)/,$(1))))

# Convert a list of paths to files in $(~) to paths in the user's home directory.
# All arguments are relative to the $(~) directory.
to_user_home = $(call convert_prefix,$(~),$(HOME),$(wildcard $(addprefix $(~)/,$(1))))

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

# Map files in the repository to the user's home directory.
force:
~/% : $(~)/% force
	$(call ensure_directory_exists,$(@D))
	$(call link,$<,$@)

# Phony targets

user_binaries := $(call to_user_home,bin/*)
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

sublime_text_3_user_preferences := $(call to_user_home,.config/sublime-text-3/Packages/User/*.sublime-settings)
all += sublime-text-3
sublime-text-3 : $(sublime_text_3_user_preferences)

.Xresources.d := $(call to_user_home,.Xresources.d/*)
all += Xresources
~/.Xresources : $(.Xresources.d)
Xresources: ~/.Xresources

all += xinitrc
xinitrc : ~/.xinitrc

all += X
X : Xresources xinitrc

all += urxvt
urxvt : Xresources

kitty_conf := $(call to_user_home,.config/kitty/*.conf)
kitty_themes := $(call to_user_home,.config/kitty/themes/*.conf)
all += kitty
kitty : $(kitty_conf) $(kitty_themes)

all += i3
i3 : ~/.config/i3/config ~/.config/i3status/config

all += mpv
mpv : ~/.config/mpv/mpv.conf

all : $(all)

.PHONY: all $(all)
.DEFAULT_GOAL := all
