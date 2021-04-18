#!/bin/sh

PWD=
case "$0" in
*/*) srcdir=`dirname $0`;;
*) srcdir="";;
esac

exec ${AUTORECONF:-autoreconf} --install --symlink "$@" ${srcdir:+"$srcdir"}
