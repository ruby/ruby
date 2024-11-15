#!/bin/bash

echo "* Show warning with bootsnap"
ruby test_warn_bootsnap.rb
echo

echo "* Show warning with bootsnap for gem with native extension"
ruby test_warn_bootsnap_rubyarchdir_gem.rb
echo

echo "* Show warning with zeitwerk"
ruby test_warn_zeitwerk.rb
echo

echo "* Show warning with bootsnap and some gem in Gemfile"
ruby test_warn_bootsnap_and_gem.rb
echo
