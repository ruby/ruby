# = timeout.rb
#
# execution timeout
#
# = Synopsis
#
#   require 'timeout'
#   status = Timeout::timeout(5) {
#     # Something that should be interrupted if it takes too much time...
#   }
#
# = Description
#
# A way of performing a potentially long-running operation in a thread, and terminating
# it's execution if it hasn't finished by a fixed amount of time.
#
# Previous versions of timeout didn't provide use a module for namespace. This version
# provides both Timeout.timeout, and a backwards-compatible #timeout.
#
# = Copyright
#
# Copyright:: (C) 2000  Network Applied Communication Laboratory, Inc.
# Copyright:: (C) 2000  Information-technology Promotion Agency, Japan

module Timeout
  # Raised by Timeout#timeout when the block times out.
  class Error < RuntimeError
  end
  class ExitException < ::Exception # :nodoc:
  end

  THIS_FILE = /\A#{Regexp.quote(__FILE__)}:/o
  CALLER_OFFSET = ((c = caller[0]) && THIS_FILE =~ c) ? 1 : 0

  # Executes the method's block.  If the block execution terminates before
  # +sec+ seconds has passed, it returns the result value of the block.
  # If not, it terminates the execution and raises +exception+ (which defaults
  # to Timeout::Error).
  #
  # Note that this is both a method of module Timeout, so you can 'include Timeout'
  # into your classes so they have a #timeout method, as well as a module method,
  # so you can call it directly as Timeout.timeout().
  def timeout(sec, klass = nil)   #:yield: +sec+
    return yield(sec) if sec == nil or sec.zero?
    exception = klass || Class.new(ExitException)
    begin
      x = Thread.current
      y = Thread.start {
        sleep sec
        x.raise exception, "execution expired" if x.alive?
      }
      return yield(sec)
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
      if y and y.alive?
        y.kill
        y.join # make sure y is dead.
      end
    end
  end

  module_function :timeout
end

# Identical to:
#
#   Timeout::timeout(n, e, &block).
#
# Defined for backwards compatibility with earlier versions of timeout.rb, see
# Timeout#timeout.
def timeout(n, e = nil, &block)
  Timeout::timeout(n, e, &block)
end

# Another name for Timeout::Error, defined for backwards compatibility with
# earlier versions of timeout.rb.
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
