require 'drb/drb'
require 'drb/extserv'

module DRbTests

class EvalAttack
  def initialize
    @four = DRb::DRbServer.new('druby://localhost:0', self, {:safe_level => 4})
  end

  def four
    DRbObject.new_with_uri(@four.uri)
  end

  def remote_class
    DRbObject.new(self.class)
  end
end

end


if __FILE__ == $0
  def ARGV.shift
    it = super()
    raise "usage: #{$0} <uri> <name>" unless it
    it
  end

  $SAFE = 1

  DRb.start_service('druby://localhost:0', DRbTests::EvalAttack.new, {:safe_level => 2})
  es = DRb::ExtServ.new(ARGV.shift, ARGV.shift)
  DRb.thread.join
  es.stop_service if es.alive?
end
