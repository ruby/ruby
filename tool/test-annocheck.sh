#!/bin/sh -eu
# Run the `tool/test-annocheck.sh [binary files]` to check security issues
# by annocheck <https://sourceware.org/annobin/>.
#
# E.g. `tool/test-annocheck.sh ruby libruby.so.3.2.0`.
#
# Note that as the annocheck binary package is not available on Ubuntu, and it
# is working in progress in Debian, this script uses Fedora container for now.
# It requires docker or podman.
# https://www.debian.org/devel/wnpp/itp.en.html
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=926470

set -x

DOCKER="$(command -v docker || command -v podman)"
TAG=ruby-fedora-annocheck
TOOL_DIR="$(dirname "${0}")"
TMP_DIR="tmp/annocheck"
DOCKER_RUN_VOLUME_OPTS=

if [ -z "${CI-}" ]; then
  # Use a volume option on local (non-CI).
  DOCKER_RUN_VOLUME_OPTS="-v $(pwd):/work"
  "${DOCKER}" build --rm -t "${TAG}" ${TOOL_DIR}/annocheck/
else
  # TODO: A temporary workaround on CI to build by copying binary files from
  # host to container without volume option, as I couldn't find a way to use
  # volume in container in container on GitHub Actions
  # <.github/workflows/compilers.yml>.
  TAG="${TAG}-copy"
  rm -rf "${TMP_DIR}"
  mkdir -p "${TMP_DIR}"
  for file in "${@}"; do
    cp -p "${file}" "${TMP_DIR}"
  done
  "${DOCKER}" build --rm -t "${TAG}" --build-arg=IN_DIR="${TMP_DIR}" -f ${TOOL_DIR}/annocheck/Dockerfile-copy .
  rm -rf "${TMP_DIR}"
fi

"${DOCKER}" run --rm -t ${DOCKER_RUN_VOLUME_OPTS} "${TAG}" annocheck --verbose ${TEST_ANNOCHECK_OPTS-} "${@}"
