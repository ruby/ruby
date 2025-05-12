# frozen_string_literal: true

require "cgi/escape"
warn <<-WARNING, uplevel: 1 if $VERBOSE
CGI::Util is removed from Ruby 3.5. Please use cgi/escape instead for CGI.escape and CGI.unescape features.
WARNING
