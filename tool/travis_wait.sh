#!/bin/bash -eu
# The modified version of `travis_wait` to output a log as the command goes.
# https://github.com/travis-ci/travis-ci/issues/4190#issuecomment-353342526

# Produce an output log every 9 minutes as the timeout without output is 10
# minutes. A job finishes with a timeout if it takes longer than 50 minutes.
# https://docs.travis-ci.com/user/customizing-the-build#build-timeouts
while sleep 9m; do
  # Print message with bash variable SECONDS.
  echo "====[ $SECONDS seconds still running ]===="
done &

echo "+ $@"
"$@"

jobs
kill %1
exit 0
