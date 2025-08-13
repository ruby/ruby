#!/bin/sh

# Clear PWD to force commands to recompute working directory
PWD=

# Figure out the source directory for this script
# configure.ac should be in the same place
case "$0" in
    */* )  srcdir=`dirname "$0"` ;; # Called with path
    *   )  srcdir="";; # Otherwise
esac

# If install-only is explicitly requested, disable symlink flags
case " $* " in
    *" -i "* | *" --install"* ) symlink_flags="" ;;
    *                         ) symlink_flags="--install --symlink" ;;
esac

exec ${AUTORECONF:-autoreconf} \
     $symlink_flags \
     "$@" \
     $srcdir
