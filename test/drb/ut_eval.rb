require 'drb/drb'
require 'drb/extserv'

class EvalAttack
  def remote_class
    DRbObject.new(self.class)
  end
end


if __FILE__ == $0
  def ARGV.shift
    it = super()
    raise "usage: #{$0} <uri> <name>" unless it
    it
  end

  $SAFE = 1

  DRb.start_service('druby://localhost:0', EvalAttack.new)
  es = DRb::ExtServ.new(ARGV.shift, ARGV.shift)
  DRb.thread.join
end
