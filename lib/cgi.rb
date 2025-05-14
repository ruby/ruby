# frozen_string_literal: true

require "cgi/escape"
warn <<-WARNING, uplevel: 1 if $VERBOSE
CGI library is removed from Ruby 3.5. Please use cgi/escape instead for CGI.escape and CGI.unescape features.
If you need to use the full features of CGI library, Please install cgi gem.
WARNING
