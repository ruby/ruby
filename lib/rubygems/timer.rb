#
# This file defines a $log variable for logging, and a time() method for
# recording timing information.
#
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems'

file, lineno = Gem.location_of_caller

warn "#{file}:#{lineno}:Warning: RubyGems' lib/rubygems/timer.rb deprecated and will be removed on or after June 2009."

$log = Object.new

# :stopdoc:
def $log.debug(message)
  Gem.debug message
end

def time(msg, width=25, &block)
  Gem.time(msg, width, &block)
end
# :startdoc:

