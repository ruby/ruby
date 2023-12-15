This directory contains tests for the bundled gems warning under the Bundler.

## Warning cases

test_warn_bundled_gems.rb:
test_warn_dependency.rb:
test_warn_dash_gem.rb:
  $ ruby test_warn_dash_gem.rb

test_warn_bundle_exec.rb:
  $ bundle exec ruby test_warn_bundle_exec.rb

test_warn_bundle_exec_shebang.rb:
  $ bundle exec ./test_warn_bundle_exec_shebang.rb

## Not warning cases

test_no_warn_dash_gem.rb:
test_no_warn_bootsnap.rb:
test_no_warn_dependency.rb:
  $ ruby test_no_warn_dash_gem.rb
