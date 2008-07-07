#--
# = timeout.rb
#
# execution timeout
#
# = Copyright
#
# Copyright:: (C) 2000  Network Applied Communication Laboratory, Inc.
# Copyright:: (C) 2000  Information-technology Promotion Agency, Japan
#
#++
#
# = Description
#
# A way of performing a potentially long-running operation in a thread, and
# terminating it's execution if it hasn't finished within fixed amount of
# time.
#
# Previous versions of timeout didn't use a module for namespace. This version
# provides both Timeout.timeout, and a backwards-compatible #timeout.
#
# = Synopsis
#
#   require 'timeout'
#   status = Timeout::timeout(5) {
#     # Something that should be interrupted if it takes too much time...
#   }
#

module Timeout

  ##
  # Raised by Timeout#timeout when the block times out.

  class Error < Interrupt
  end
  class ExitException < ::Exception # :nodoc:
  end

  THIS_FILE = /\A#{Regexp.quote(__FILE__)}:/o
  CALLER_OFFSET = ((c = caller[0]) && THIS_FILE =~ c) ? 1 : 0

  ##
  # Executes the method's block. If the block execution terminates before +sec+
  # seconds has passed, it returns true. If not, it terminates the execution
  # and raises +exception+ (which defaults to Timeout::Error).
  #
  # Note that this is both a method of module Timeout, so you can 'include
  # Timeout' into your classes so they have a #timeout method, as well as a
  # module method, so you can call it directly as Timeout.timeout().

  def timeout(sec, klass = nil)
    return yield if sec == nil or sec.zero?
    raise ThreadError, "timeout within critical session" if Thread.critical
    exception = klass || Class.new(ExitException)
    begin
      x = Thread.current
      y = Thread.start {
        sleep sec
        x.raise exception, "execution expired" if x.alive?
      }
      yield sec
      #    return true
    rescue exception => e
      rej = /\A#{Regexp.quote(__FILE__)}:#{__LINE__-4}\z/o
      (bt = e.backtrace).reject! {|m| rej =~ m}
      level = -caller(CALLER_OFFSET).size
      while THIS_FILE =~ bt[level]
        bt.delete_at(level)
        level += 1
      end
      raise if klass            # if exception class is specified, it
                                # would be expected outside.
      raise Error, e.message, e.backtrace
    ensure
      y.kill if y and y.alive?
    end
  end

  module_function :timeout

end

##
# Identical to:
#
#   Timeout::timeout(n, e, &block).
#
# Defined for backwards compatibility with earlier versions of timeout.rb, see
# Timeout#timeout.

def timeout(n, e = nil, &block) # :nodoc:
  Timeout::timeout(n, e, &block)
end

##
# Another name for Timeout::Error, defined for backwards compatibility with
# earlier versions of timeout.rb.

TimeoutError = Timeout::Error # :nodoc:

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

