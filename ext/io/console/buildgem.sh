#!/bin/sh -e
cd ${0%/*}
trap "mv depend.$$ depend" 0 2
${RUBY-ruby} -i.$$ -pe 'exit if /^win32_vk/' depend
${GEM-gem} build io-console.gemspec
