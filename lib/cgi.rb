# frozen_string_literal: true

require "cgi/escape"
warn <<-WARNING, uplevel: Gem::BUNDLED_GEMS.uplevel if $VERBOSE
CGI library is removed from Ruby 4.0. Please use cgi/escape instead for CGI.escape and CGI.unescape features.

If you need to use the full features of CGI library, please add 'gem "cgi"' to your script
or use Bundler to ensure you are using the cgi gem instead of this file.
WARNING
