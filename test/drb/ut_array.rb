# frozen_string_literal: false
require 'drb/drb'
require 'drb/extserv'

if __FILE__ == $0
  def ARGV.shift
    it = super()
    raise "usage: #{$0} <uri> <name>" unless it
    it
  end

  DRb.start_service('druby://localhost:0', [1, 2, 'III', 4, "five", 6])
  es = DRb::ExtServ.new(ARGV.shift, ARGV.shift)
  DRb.thread.join
  es.stop_service if es.alive?
end

