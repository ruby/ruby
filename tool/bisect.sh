#!/bin/sh
# usage:
#   edit $(srcdir)/test.rb
#   git bisect start `git svn find-rev <rBADREV>` `git svn find-rev <rGOODREV>`
#   cd <builddir>
#   make bisect (or bisect-ruby for full ruby)

if [ "x" = "x$MAKE" ]; then
  MAKE=make
fi

case $1 in
  miniruby | ruby ) # (miniruby|ruby) <srcdir>
    srcdir="$2"
    builddir=`pwd` # assume pwd is builddir
    path="$builddir/_bisect.sh"
    echo "path: $path"
    cp "$0" "$path"
    cd "$srcdir"
    set -x
    exec git bisect run "$path" "run-$1"
    ;;
  run-miniruby )
    $MAKE srcs || exit 125
    cd "${0%/*}" || exit 125 # assume a copy of this script is in builddir
    $MAKE Makefile || exit 125
    $MAKE mini || exit 125
    $MAKE run || exit 1
    ;;
  run-ruby )
    $MAKE srcs || exit 125
    cd "${0%/*}" || exit 125 # assume a copy of this script is in builddir
    $MAKE Makefile || exit 125
    $MAKE program || exit 125
    $MAKE runruby || exit 1
    ;;
  "" )
    echo foo bar
    ;;
  * )
    echo unknown command "'$1'" 1>&2
    exit 1
    ;;
esac
exit 0
