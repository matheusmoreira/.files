#
# GNU Make based .file manager
# Copyright © 2018-2024 Matheus Afonso Martins Moreira <matheus@matheusmoreira.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

# Disable built-in make variables and rules
MAKEFLAGS += --no-builtin-variables --no-builtin-rules

makefile := $(abspath $(lastword $(MAKEFILE_LIST)))
dotfiles := $(abspath $(dir $(makefile)))
~ := $(abspath $(dotfiles)/~)

# Commands to use for directory and symbolic link creation.
mkdir ?= mkdir -p $(1)
ln ?= ln -snf $(1) $(2)

# Determines whether the given path exists and is a directory.
# Only existing directories contain a "." entry.
directory? = $(wildcard $(1)/.)

# Generates a command that creates the given directory.
# Generates the empty string if the directory already exists.
ensure_directory_exists = $(if $(call directory?,$(1)),,$(call mkdir,$(1)))

# Generates a command to link $(1) to $(2).
link = $(call ln,$(2),$(1))

# Template for the definition of symbolic link creation rules.
# The recipe links all targets in $(1) to their counterparts in $(2).
# The targets are always updated. The target's directory is created if needed.
#
# $(1) = Prefix of the symbolic link
# $(2) = Prefix of the symbolic link's target
#
# Rules generated:
#
#     $(1)/% : $(2)/%
#
define rule.template
$(1)/% : $(2)/% force
	$$(call ensure_directory_exists,$$(@D))
	$$(call link,$$@,$$<)
endef

# Defines a rule that links all targets in $(1) to their counterparts in $(2).
rule.define = $(eval $(call rule.template,$(1),$(2)))

# Converts the list of paths specified in $(3) from paths prefixed by $(1)
# to paths prefixed by $(2).
convert_prefix = $(patsubst $(1)/%,$(2)/%,$(3))

# Template for the definition of prefix conversion functions
# that convert between the user's home directory and dotfiles repository.
#
# $(1) = Type of prefix conversion
# $(2) = Home directory prefix
# $(3) = Dotfiles repository prefix
#
# Functions generated:
#
#     $(1).to_dotfiles         Converts paths to files in $(2) to paths in $(3).
#     $(1).to_user             Converts paths to files in $(3) to paths in $(2).
#     $(1).user_to_dotfiles    Converts paths relative to $(2) to absolute paths in $(3).
#     $(1).dotfiles_to_user    Converts paths relative to $(3) to absolute paths in $(2).
#
define prefix_conversion_functions.template
$(1).to_dotfiles = $$(call convert_prefix,$(2),$(3),$$(1))
$(1).to_user = $$(call convert_prefix,$(3),$(2),$$(1))

$(1).user_to_dotfiles = $$(call $(1).to_dotfiles,$$(wildcard $$(addprefix $(2)/,$$(1))))
$(1).dotfiles_to_user = $$(call $(1).to_user,$$(wildcard $$(addprefix $(3)/,$$(1))))
endef

# Defines path conversion functions for the given type, home directory prefix and dotfiles repository prefix.
prefix_conversion_functions.define = $(eval $(call prefix_conversion_functions.template,$(1),$(2),$(3)))

# Create symbolic links in $(HOME) pointing at their counterparts in $(~).
$(call rule.define,$(HOME),$(~))

# ~.to_dotfiles
# ~.to_user
# ~.user_to_dotfiles
# ~.dotfiles_to_user
$(call prefix_conversion_functions.define,~,$$(HOME),$$(~))

# XDG Base Directory Specification
# https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
#
# Files in the repository are stored in the default directories.
# Links in $(HOME) take the XDG variables into account.

# Template for the definition of rules, variables and path conversion functions
# for the user's XDG directories.
#
# $(1) = Type of XDG directory
# $(2) = Default directory, used if XDG variable not set
#
# Rules generated:
#
#     $(XDG_$(1)_HOME)/% : $(XDG_$(1)_HOME.dotfiles)/%
#
# Variables generated:
#
#     XDG_$(1)_HOME             Directory set by user or the default directory
#     XDG_$(1)_HOME.default     Default XDG_$(1)_HOME directory
#     XDG_$(1)_HOME.dotfiles    The XDG_$(1)_HOME directory in the dotfiles repository
#
# Functions generated:
#
#     $(1).to_dotfiles         Converts paths to files in $(XDG_$(1)_HOME)
#                              to paths in $(XDG_$(1)_HOME.dotfiles).
#     $(1).to_user             Converts paths to files in $(XDG_$(1)_HOME.dotfiles)
#                              to paths in $(XDG_$(1)_HOME).
#     $(1).user_to_dotfiles    Converts paths relative to $(XDG_$(1)_HOME)
#                              to absolute paths in $(XDG_$(1)_HOME.dotfiles).
#     $(1).dotfiles_to_user    Converts paths relative to $(XDG_$(1)_HOME.dotfiles)
#                              to absolute paths in $(XDG_$(1)_HOME).
#
define XDG.template
XDG_$(1)_HOME.default := $$(HOME)/$(2)
XDG_$(1)_HOME.dotfiles := $$(call ~.to_dotfiles,$$(XDG_$(1)_HOME.default))
XDG_$(1)_HOME ?= $$(XDG_$(1)_HOME.default)

$(call prefix_conversion_functions.template,$(1),$$(XDG_$(1)_HOME),$$(XDG_$(1)_HOME.dotfiles))
$(call rule.template,$$(XDG_$(1)_HOME),$$(XDG_$(1)_HOME.dotfiles))
endef

# Defines XDG rules, variables and functions for the given type and default directory.
XDG.define = $(eval $(call XDG.template,$(1),$(2)))

# $(XDG_DATA_HOME)/% : $(XDG_DATA_HOME.dotfiles)/%
#
# XDG_DATA_HOME
# XDG_DATA_HOME.default
# XDG_DATA_HOME.dotfiles
#
# DATA.to_dotfiles
# DATA.to_user
# DATA.user_to_dotfiles
# DATA.dotfiles_to_user
$(call XDG.define,DATA,.local/share)

# $(XDG_CONFIG_HOME)/% : $(XDG_CONFIG_HOME.dotfiles)/%
#
# XDG_CONFIG_HOME
# XDG_CONFIG_HOME.default
# XDG_CONFIG_HOME.dotfiles
#
# CONFIG.to_dotfiles
# CONFIG.to_user
# CONFIG.user_to_dotfiles
# CONFIG.dotfiles_to_user
$(call XDG.define,CONFIG,.config)

# Some directories are not part of the XDG specification
# but are widely used in practice.
#
#     $ systemd-path user-binaries
#     ~/.local/bin

# $(XDG_BIN_HOME)/% : $(XDG_BIN_HOME.dotfiles)/%
#
# XDG_BIN_HOME
# XDG_BIN_HOME.default
# XDG_BIN_HOME.dotfiles
#
# BIN.to_dotfiles
# BIN.to_user
# BIN.user_to_dotfiles
# BIN.dotfiles_to_user
$(call XDG.define,BIN,.local/bin)

# GNU Privacy Guard
# https://www.gnupg.org/documentation/manuals/gnupg/
#
# Files in the repository are stored in the default directories.
# Links in $(GNUPGHOME) take the environment variable into account.

# GNUPGHOME
# GNUPGHOME.default
# GNUPGHOME.dotfiles
GNUPGHOME.default := $(HOME)/.gnupg
GNUPGHOME.dotfiles := $(call ~.to_dotfiles,$(GNUPGHOME.default))
GNUPGHOME ?= $(GNUPGHOME.default)

# GNUPGHOME.to_dotfiles
# GNUPGHOME.to_user
# GNUPGHOME.user_to_dotfiles
# GNUPGHOME.dotfiles_to_user
$(call prefix_conversion_functions.define,GNUPGHOME,$(GNUPGHOME),$(GNUPGHOME.dotfiles))

# $(GNUPGHOME)/% : $(GNUPGHOME.dotfiles)/%
$(call rule.define,$(GNUPGHOME),$(GNUPGHOME.dotfiles))

# Phony targets

user_binaries := $(call BIN.dotfiles_to_user,*)
all += bin
bin : $(user_binaries)

all += bash
bash : ~/.bash_profile ~/.bashrc

all += git
git : $(call CONFIG.dotfiles_to_user,git/config)

all += ssh
ssh : ~/.ssh/config

all += vim
vim : ~/.vimrc

all += nano
nano : $(call CONFIG.dotfiles_to_user,nano/nanorc)

all += gpg
gpg : $(call GNUPGHOME.dotfiles_to_user,*.conf)

all += gdb
gdb : $(call CONFIG.dotfiles_to_user,gdb/*)

all += shellcheck
shellcheck : $(call CONFIG.dotfiles_to_user,shellcheckrc)

all += tidy
tidy : ~/.tidyrc

sublime_text_3_user_preferences := $(call CONFIG.dotfiles_to_user,sublime-text-3/Packages/User/*.sublime-settings)
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

all += terminals kitty foot
terminals : kitty foot

foot : $(call CONFIG.dotfiles_to_user,foot/foot.ini)

kitty_conf := $(call CONFIG.dotfiles_to_user,kitty/*.conf)
kitty_themes := $(call CONFIG.dotfiles_to_user,kitty/themes/*.conf)
kitty_fonts := $(call CONFIG.dotfiles_to_user,kitty/fonts/*.conf)
kitty_performance := $(call CONFIG.dotfiles_to_user,kitty/performance/*.conf)
kitty : $(kitty_conf) $(kitty_themes) $(kitty_fonts) $(kitty_performance)

all += i3
i3 : $(call CONFIG.dotfiles_to_user,i3/config i3status/config) $(call BIN.dotfiles_to_user,nvidia-smi.py)

all += mpv
mpv : $(call CONFIG.dotfiles_to_user,mpv/mpv.conf)

all += termux
termux : ~/.termux/termux.properties

all += irc irssi
irc : irssi
irssi : ~/.irssi/config

all += email msmtp
email : msmtp
msmtp : ~/.msmtprc

all : $(all)
basic : bash git ssh vim nano

force:
.PHONY: all $(all)
.DEFAULT_GOAL := basic
