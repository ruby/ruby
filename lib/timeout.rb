#
# timeout.rb -- execution timeout
#
# Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
# Copyright (C) 2000  Information-technology Promotion Agency, Japan
#
#= SYNOPSIS
#
#   require 'timeout'
#   status = timeout(5) {
#     # something may take time
#   }
#
#= DESCRIPTION
#
# timeout executes the block.  If the block execution terminates successfully
# before timeout, it returns true.  If not, it terminates the execution and
# raise TimeoutError exception.
#
#== Parameters
#
#  : timout
#
#    The time in seconds to wait for block teminatation.   
#
#=end

class TimeoutError<StandardError
end

def timeout(sec)
  begin
    x = Thread.current
    y = Thread.start {
      sleep sec
      x.raise TimeoutError, "execution expired" if x.alive?
    }
    yield sec
    return true
  ensure
    Thread.kill y if y.alive?
  end
end
