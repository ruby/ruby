#!/bin/bash

echo "* Show warning sub-feature like bigdecimal/util"
ruby test_warn_sub_feature.rb
echo

echo "* Show warning with bootsnap"
ruby test_warn_bootsnap.rb
echo

echo "* Show warning with bootsnap for gem with native extension"
ruby test_warn_bootsnap_rubyarchdir_gem.rb
echo

echo "* Show warning with zeitwerk"
ruby test_warn_zeitwerk.rb
echo

echo "* Don't show warning bigdecimal/util when bigdecimal on Gemfile"
ruby test_no_warn_sub_feature.rb
echo

echo "* Show warning with bootsnap and some gem in Gemfile"
ruby test_warn_bootsnap_and_gem.rb
echo
