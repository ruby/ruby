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
#    The time in seconds to wait for block termination.   
#
#  : [exception]
#
#    The exception class to be raised on timeout.
#
#=end

module Timeout
  class Error<Interrupt
  end

  def timeout(sec, exception=Error)
    return yield if sec == nil or sec.zero?
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
  module_function :timeout
end

# compatible
def timeout(n, e=Timeout::Error, &block)
  Timeout::timeout(n, e, &block)
end
TimeoutError = Timeout::Error

if __FILE__ == $0
  p timeout(5) {
    45
  }
  p timeout(5, TimeoutError) {
    45
  }
  p timeout(nil) {
    54
  }
  p timeout(0) {
    54
  }
  p timeout(5) {
    loop {
      p 10
      sleep 1
    }
  }
end
