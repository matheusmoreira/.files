#!/bin/sh

user_Xresources=~/.Xresources
user_Xmodmap=~/.Xmodmap
system_Xresources=/etc/X11/xinit/.Xresources
system_Xmodmap=/etc/X11/xinit/.Xmodmap

if [ -f "$system_Xresources" ]
then
  xrdb -merge "$system_Xresources"
fi

if [ -f "$system_Xmodmap" ]
then
  xmodmap "$system_Xmodmap"
fi

if [ -f "$user_Xresources" ]
then
  xrdb -merge "$user_Xresources"
fi

if [ -f "$user_Xmodmap" ]
then
  xmodmap "$user_Xmodmap"
fi

if [ -d /etc/X11/xinit/xinitrc.d ]
then
  for shell_script in /etc/X11/xinit/xinitrc.d/?*.sh
  do
    [ -x "$shell_script" ] && source "$shell_script"
  done
  unset shell_script
fi

exec i3
