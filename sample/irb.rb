#!/usr/bin/env ruby
#
#   irb.rb - intaractive ruby
#   	$Release Version: 0.6 $
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(Nippon Rational Inc.)
#
# --
# Usage:
#
#   irb.rb [options] file_name opts
#
#

require "irb/main"

if __FILE__ == $0
  IRB.start(__FILE__)
else
  # check -e option
  tmp = ENV["TMP"] || ENV["TMPDIR"] || "/tmp"
  if %r|#{tmp}/rb| =~ $0
    IRB.start(__FILE__)
  else
    IRB.initialize(__FILE__)
  end
end
