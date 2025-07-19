#!/bin/sh

# Clear PWD to force commands to recompute working directory
PWD=

# Figure out the source directory for this script
# configure.ac should be in the same place
srcdir() {
  case "$0" in
    */* ) dirname "$0" ;; # Called with path
    *   ) echo ""    ;; # Otherwise
  esac
}

# If install-only is explicitly requested, disbale symlink flags
symlink_flags() {
  case " $* " in
    *" -i "* | *" --install"* ) echo "" ;;
    *                         ) echo "--install --symlink" ;;
  esac
}

exec ${AUTORECONF:-autoreconf} \
     $(symlink_flags) \
     "$@" \
     $(srcdir)
