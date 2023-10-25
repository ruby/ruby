#!/bin/sh

PWD=
case "$0" in
*/*) srcdir=`dirname $0`;;
*) srcdir="";;
esac

symlink='--install --symlink'
case " $* " in
    *" -i "*|*" --install "*)
        # reset to copy missing standard auxiliary files, instead of symlinks
        symlink=
        ;;
esac

exec ${AUTORECONF:-autoreconf} ${symlink} "$@" ${srcdir:+"$srcdir"}
