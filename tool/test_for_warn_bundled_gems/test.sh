#!/bin/bash

echo "* Show warning require and LoadError"
ruby test_warn_bundled_gems.rb

echo "* Show warning when bundled gems called as dependency"
ruby test_warn_dependency.rb

echo "* Show warning sub-feature like bigdecimal/util"
ruby test_warn_sub_feature.rb

echo "* Show warning dash gem like net/smtp"
ruby test_warn_dash_gem.rb

echo "* Show warning when bundle exec with ruby and script"
bundle exec ruby test_warn_bundle_exec.rb

echo "* Show warning when bundle exec with shebang's script"
bundle exec ./test_warn_bundle_exec_shebang.rb

echo "* Don't show warning bundled gems on Gemfile"
ruby test_no_warn_dependency.rb

echo "* Don't show warning with bootsnap"
ruby test_no_warn_bootsnap.rb

echo "* Don't show warning with net/smtp when net-smtp on Gemfile"
ruby test_no_warn_dash_gem.rb

echo "* Don't show warning bigdecimal/util when bigdecimal on Gemfile"
ruby test_no_warn_sub_feature.rb
