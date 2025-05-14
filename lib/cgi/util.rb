# frozen_string_literal: true

require "cgi/escape"
warn <<-WARNING, uplevel: Gem::BUNDLED_GEMS.uplevel if $VERBOSE
CGI::Util is removed from Ruby 3.5. Please use cgi/escape instead for CGI.escape and CGI.unescape features.
WARNING
