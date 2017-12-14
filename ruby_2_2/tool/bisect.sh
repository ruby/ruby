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
    srcdir=$2
    builddir=`pwd` # assume pwd is builddir
    path=$builddir/_bisect.sh
    echo "path: $path"
    cp $0 $path
    cd $srcdir
    echo "git bisect run $path run-$1"
    git bisect run $path run-$1
    ;;
  run-miniruby )
    cd ${0%/*} # assume a copy of this script is in builddir
    $MAKE Makefile
    $MAKE mini || exit 125
    $MAKE run || exit 1
    ;;
  run-ruby )
    cd ${0%/*} # assume a copy of this script is in builddir
    $MAKE Makefile
    $MAKE program || exit 125
    $MAKE runruby || exit 1
    ;;
  "" )
    echo foo bar
    ;;
  * )
    echo unkown command "'$cmd'"
    ;;
esac
exit 0
