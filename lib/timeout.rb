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

class TimeoutError<Interrupt
end

def timeout(sec, exception=TimeoutError)
  return yield if sec == nil
  begin
    x = Thread.current
    y = Thread.start {
      sleep sec
      x.raise exception, "execution expired" if x.alive?
    }
    yield sec
#    return true
  ensure
    y.kill if y and y.alive?
  end
end

if __FILE__ == $0
  p timeout(5) {
    45
  }
  p timeout(5) {
    loop {
      p 10
      sleep 1
    }
  }
end
