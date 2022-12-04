# -*- BASH -*-
# Manage functions used on a CI.
# Run `. tool/ci_functions.sh` to use it.

# Create options with patterns `-n !/name1/ -n !/name2/ ..` to exclude the test
# method names by the method names `name1 name2 ..`.
# See `ruby tool/test/runner.rb --help` `-n` option.
function ci_to_excluded_test_opts {
  local tests_str="${1}"
  # Use the backward matching `!/name$/`, as the perfect matching doesn't work.
  # https://bugs.ruby-lang.org/issues/16936
  ruby <<EOF
    opts = "${tests_str}".split.map { |test| "-n \!/#{test}\$$/" }
    puts opts.join(' ')
EOF
  return 0
}

# Create options with patterns `-n name1 -n name2 ..` to include the test
# method names by the method names `name1 name2 ..`.
# See `ruby tool/test/runner.rb --help` `-n` option.
function ci_to_included_test_opts {
  local tests_str="${1}"
  ruby <<EOF
    opts = "${tests_str}".split.map { |test| "-n #{test}" }
    puts opts.join(' ')
EOF
  return 0
}
