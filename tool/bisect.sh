#!/bin/sh
# usage:
#   edit $(srcdir)/test.rb
#   git bisect start <bad> <good>
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
    prep=mini
    run=run
    ;;
  run-ruby )
    prep=program
    run=runruby
    ;;
  "" )
    echo missing command 1>&2
    exit 1
    ;;
  * )
    echo unknown command "'$1'" 1>&2
    exit 1
    ;;
esac

case "$0" in
*/*)
    # assume a copy of this script is in builddir
    cd `echo "$0" | sed 's:\(.*\)/.*:\1:'` || exit 125
    ;;
esac
for target in srcs Makefile $prep; do
    $MAKE $target || exit 125
done
exec $MAKE $run
