#! /bin/bash

# Copyright (c) 2024 Ruby developers.  All rights reserved.
#
# This file is  a part of the programming language  Ruby.  Permission is hereby
# granted, to  either redistribute and/or  modify this file, provided  that the
# conditions  mentioned in  the file  COPYING are  met.  Consult  the file  for
# details.

grouped()
{
    echo "::group::${@}"
    "${@}"
    echo "::endgroup::"
}

set -e
set -u
set -o pipefail

srcdir="/github/workspace/src"
builddir="$(mktemp -dt)"

export GITHUB_WORKFLOW='Compilations'
export CONFIGURE_TTY='never'
export RUBY_DEBUG='ci rgengc'
export RUBY_TESTOPTS='-q --color=always --tty=no'
export RUBY_DEBUG_COUNTER_DISABLE='1'
export GNUMAKEFLAGS="-j$((1 + $(nproc)))"

case "x${INPUT_ENABLE_SHARED}" in
x | xno | xfalse )
    enable_shared='--disable-shared'
    ;;
*)
    enable_shared='--enable-shared'
    ;;
esac

pushd ${builddir}

grouped git config --global --add safe.directory ${srcdir}

grouped ${srcdir}/configure        \
    -C                             \
    --with-gcc="${INPUT_WITH_GCC}" \
    --enable-debug-env             \
    --disable-install-doc          \
    --with-ext=-test-/cxxanyargs,+ \
    ${enable_shared}               \
    ${INPUT_APPEND_CONFIGURE}      \
    CFLAGS="${INPUT_CFLAGS}"       \
    CXXFLAGS="${INPUT_CXXFLAGS}"   \
    optflags="${INPUT_OPTFLAGS}"   \
    cppflags="${INPUT_CPPFLAGS}"   \
    debugflags='-ggdb3' # -g0 disables backtraces when SEGV.  Do not set that.

popd

if [[ -n "${INPUT_STATIC_EXTS}" ]]; then
    echo "::group::ext/Setup"
    set -x
    mkdir ${builddir}/ext
    (
        for ext in ${INPUT_STATIC_EXTS}; do
            echo "${ext}"
        done
    ) >> ${builddir}/ext/Setup
    set +x
    echo "::endgroup::"
fi

if [ -n "$INPUT_TEST_ALL" ]; then
  tests=" -- $INPUT_TEST_ALL"
else
  tests=" -- ruby -ext-"
fi

pushd ${builddir}

grouped make showflags
grouped make all
# grouped make install

# Run only `make test` by default. Run other tests if specified.
grouped make test
if [[ -n "$INPUT_CHECK" ]]; then grouped make test-tool; fi
if [[ -n "$INPUT_CHECK" || -n "$INPUT_TEST_ALL" ]]; then grouped make test-all TESTS="$tests"; fi
if [[ -n "$INPUT_CHECK" || -n "$INPUT_TEST_SPEC" ]]; then grouped env CHECK_LEAKS=true make test-spec MSPECOPT="$INPUT_TEST_SPEC"; fi
