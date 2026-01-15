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

# Apply $(srcdir)/bisect.patch to build if exists
# e.g., needs 5c2508060b~2..5c2508060b to use Bison 3.5.91.
if [ -f bisect.patch ]; then
    if ! patch -p1 -N < bisect.patch || git diff --no-patch --exit-code; then
        exit 125
    fi
    git status
    exec=
else
    exec=exec
fi

case "$0" in
*/*)
    # assume a copy of this script is in builddir
    cd `echo "$0" | sed 's:\(.*\)/.*:\1:'` || exit 125
    ;;
esac
for target in srcs Makefile $prep; do
    $MAKE $target || exit 125
done
$exec $MAKE $run
status=$?
git checkout -f HEAD
exit $status
