#!/bin/bash

set -ex

# Definitions
CONFIG_FLAG=
JOBS=-j`nproc`

# Preparation
echo JOBS=$JOBS
uname -a
uname -r
rm -fr .ext autom4te.cache
echo $TERM
> config.status
sed -f tool/prereq.status Makefile.in common.mk > Makefile
make update-config_files
make touch-unicode-files
make -s $JOBS srcs UNICODE_FILES=.
requests=; for req in ${RUBYSPEC_PULL_REQUEST//,/ }; do
  requests=\"$requests +refs/pull/$req/merge:\";
done
${requests:+git -C spec/ruby -c user.email=none -c user.name=none pull --no-edit origin $requests}
${requests:+git -C spec/ruby log --oneline origin/master..@}
rm config.status Makefile rbconfig.rb .rbconfig.time
mkdir build config_1st config_2nd
chmod -R a-w .
chmod u+w build config_1st config_2nd
cd build
../configure -C --disable-install-doc --prefix=/tmp/ruby-prefix --with-gcc=$CC $CONFIG_FLAG
cp -pr config.cache config.status .ext/include ../config_1st
make reconfig
cp -pr config.cache config.status .ext/include ../config_2nd
(cd .. && exec diff -ru config_1st config_2nd)
make -s $JOBS && make install

# Test
make -s test TESTOPTS=--color=never
make -s $JOBS test-all -o exts TESTOPTS='-q --color=never --job-status=normal' RUBY_FORCE_TEST_JIT=1
make -s $JOBS test-spec MSPECOPT=-j
