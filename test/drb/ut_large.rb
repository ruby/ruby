require 'drb/drb'
require 'drb/extserv'
require 'timeout'

module DRbTests

class DRbLarge
  include DRbUndumped

  def size(ary)
    ary.size
  end

  def sum(ary)
    ary.inject(:+)
  end

  def multiply(ary)
    ary.inject(:*)
  end

  def avg(ary)
    (ary.inject(:+).to_f) / (ary.count)
  end

  def median(ary)
    (ary.sort[(ary.length - 1) / 2] + ary.sort[ary.length / 2]) / 2.0
  end

  def arg_test(*arg)
    # nop
  end
end

end

if __FILE__ == $0
  def ARGV.shift
    it = super()
    raise "usage: #{$0} <manager-uri> <name>" unless it
    it
  end

  DRb::DRbServer.default_argc_limit(3)
  DRb::DRbServer.default_load_limit(100000)
  DRb.start_service('druby://localhost:0', DRbTests::DRbLarge.new)
  es = DRb::ExtServ.new(ARGV.shift, ARGV.shift)
  DRb.thread.join
  es.stop_service if es.alive?
end

