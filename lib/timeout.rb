#
# timeout.rb -- execution timeout
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
      x.raise TimeoutError, "execution expired" if x.status
    }
    yield sec
    return true
  ensure
    Thread.kill y if y.status
  end
end
