#! /usr/local/bin/ruby

require "thread"
require "observer"

class Tick
  include Observable
  def initialize
    Thread.start do
      while TRUE
	sleep 0.999
	changed
	notify_observers(Time.now.strftime("%H:%M:%S"))
      end
    end
  end
end

class Clock
  def initialize
    @tick = Tick.new
    @tick.add_observer(self)
  end
  def update(time)
    print "\e[8D", time
    STDOUT.flush
  end
end

clock = Clock.new
sleep
