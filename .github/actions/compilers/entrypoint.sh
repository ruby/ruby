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
export GNUMAKEFLAGS="-j$((1 + $(nproc --all)))"

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

btests=''
tests=''
spec_opts=''

# Launchable
setup_launchable() {
    pushd ${srcdir}
    # To prevent a slowdown in CI, disable request retries when the Launchable server is unstable.
    export LAUNCHABLE_SKIP_TIMEOUT_RETRY=1
    export LAUNCHABLE_COMMIT_TIMEOUT=1
    # Launchable creates .launchable file in the current directory, but cannot a file to ${srcdir} directory.
    # As a workaround, we set LAUNCHABLE_SESSION_DIR to ${builddir}.
    export LAUNCHABLE_SESSION_DIR=${builddir}
    local github_ref="${GITHUB_REF//\//_}"
    local build_name="${github_ref}"_"${GITHUB_PR_HEAD_SHA}"
    btest_report_path='launchable_bootstraptest.json'
    test_report_path='launchable_test_all.json'
    test_spec_report_path='launchable_test_spec_report'
    test_all_session_file='launchable_test_all_session.txt'
    btest_session_file='launchable_btest_session.txt'
    test_spec_session_file='launchable_test_spec_session.txt'
    btests+=--launchable-test-reports="${btest_report_path}"
    echo "::group::Setup Launchable"
    launchable record build --name "${build_name}" || true
    launchable record session \
        --build "${build_name}" \
        --flavor test_task=test \
        --flavor workflow=Compilations \
        --flavor with-gcc="${INPUT_WITH_GCC}" \
        --flavor CFLAGS="${INPUT_CFLAGS}" \
        --flavor CXXFLAGS="${INPUT_CXXFLAGS}" \
        --flavor optflags="${INPUT_OPTFLAGS}" \
        --flavor cppflags="${INPUT_CPPFLAGS}" \
        --test-suite btest \
        > "${builddir}"/${btest_session_file} \
        || true
    if [ "$INPUT_CHECK" = "true" ]; then
        tests+=--launchable-test-reports="${test_report_path}"
        launchable record session \
            --build "${build_name}" \
            --flavor test_task=test-all \
            --flavor workflow=Compilations \
            --flavor with-gcc="${INPUT_WITH_GCC}" \
            --flavor CFLAGS="${INPUT_CFLAGS}" \
            --flavor CXXFLAGS="${INPUT_CXXFLAGS}" \
            --flavor optflags="${INPUT_OPTFLAGS}" \
            --flavor cppflags="${INPUT_CPPFLAGS}" \
            --test-suite test-all \
            > "${builddir}"/${test_all_session_file} \
            || true
        mkdir "${builddir}"/"${test_spec_report_path}"
        spec_opts+=--launchable-test-reports="${test_spec_report_path}"
        launchable record session \
            --build "${build_name}" \
            --flavor test_task=test-spec \
            --flavor workflow=Compilations \
            --flavor with-gcc="${INPUT_WITH_GCC}" \
            --flavor CFLAGS="${INPUT_CFLAGS}" \
            --flavor CXXFLAGS="${INPUT_CXXFLAGS}" \
            --flavor optflags="${INPUT_OPTFLAGS}" \
            --flavor cppflags="${INPUT_CPPFLAGS}" \
            --test-suite test-spec \
            > "${builddir}"/${test_spec_session_file} \
            || true
    fi
    echo "::endgroup::"
    trap launchable_record_test EXIT
}
launchable_record_test() {
    pushd "${builddir}"
    grouped launchable record tests --session "$(cat "${btest_session_file}")" raw "${btest_report_path}" || true
    if [ "$INPUT_CHECK" = "true" ]; then
        grouped launchable record tests --session "$(cat "${test_all_session_file}")" raw "${test_report_path}" || true
        grouped launchable record tests --session "$(cat "${test_spec_session_file}")" raw "${test_spec_report_path}"/* || true
    fi
}
if [ "$LAUNCHABLE_ENABLED" = "true" ]; then
    setup_launchable
fi

pushd ${builddir}

grouped make showflags
grouped make all
grouped make test BTESTS="${btests}"

[[ -z "${INPUT_CHECK}" ]] && exit 0

if [ "$INPUT_CHECK" = "true" ]; then
  tests+=" -- ruby -ext-"
else
  tests+=" -- $INPUT_CHECK"
fi

# grouped make install
grouped make test-tool
grouped make test-all TESTS="$tests"
grouped env CHECK_LEAKS=true make test-spec MSPECOPT="$INPUT_MSPECOPT" SPECOPTS="${spec_opts}"
