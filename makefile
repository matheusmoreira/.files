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

all : $(all)

.PHONY: all $(all)
