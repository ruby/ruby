# frozen_string_literal: false
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
    return if ary.empty?
    if ary.any? {|n| n.is_a? String}
      raise TypeError
    else
      sum(ary).to_f / ary.count
    end
  end

  def median(ary)
    return if ary.empty?
    if ary.any? {|n| n.is_a? String}
      raise TypeError
    else
      avg ary.sort[((ary.length - 1) / 2)..(ary.length / 2)]
    end
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

