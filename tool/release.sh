#!/bin/bash
# Bash version 3.2+ is required for regexp
# Usage:
#   tool/release.sh 3.0.0
#   tool/release.sh 3.0.0-rc1

EXTS='.tar.gz .tar.xz .zip'
if [[ -n $AWS_ACCESS_KEY_ID ]]; then
  AWS_CLI_OPTS=""
else
  AWS_CLI_OPTS="--profile ruby"
fi

ver=$1
if [[ $ver =~ ^([1-9]\.[0-9])\.([0-9]|[1-9][0-9]|0-(preview[1-9]|rc[1-9]))$ ]]; then
  :
else
  echo $ver is not valid release version
  exit 1
fi

short=${BASH_REMATCH[1]}
echo $ver
echo $short
for ext in $EXTS; do
  aws $AWS_CLI_OPTS s3 cp s3://ftp.r-l.o/pub/tmp/ruby-$ver-draft$ext s3://ftp.r-l.o/pub/ruby/$short/ruby-$ver$ext
done
