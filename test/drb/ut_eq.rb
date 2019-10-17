# frozen_string_literal: false
require 'drb/drb'
require 'drb/extserv'

module DRbTests

class Foo
  include DRbUndumped
end

class Bar
  include DRbUndumped
  def initialize
    @foo = Foo.new
  end
  attr_reader :foo

  def foo?(foo)
    @foo == foo
  end
end

end

if __FILE__ == $0
  def ARGV.shift
    it = super()
    raise "usage: #{$0} <uri> <name>" unless it
    it
  end

  DRb.start_service('druby://localhost:0', DRbTests::Bar.new)
  es = DRb::ExtServ.new(ARGV.shift, ARGV.shift)
  DRb.thread.join
  es.stop_service if es.alive?
end

