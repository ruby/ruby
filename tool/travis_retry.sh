#!/bin/sh -eu
# The modified version of `travis_retry` to support custom backoffs, which is used by .travis.yml.
# https://github.com/travis-ci/travis-build/blob/master/lib/travis/build/bash/travis_retry.bash

for sleep in 0 ${WAITS:- 1 25 100}; do
  sleep "$sleep"

  echo "+ $@"
  if "$@"; then
    exit 0
  fi
done
exit 1
