#!/usr/bin/env ruby
# This script is a re-implementation of tktimer.rb with TkTimer(TkAfter) class.

require "tk"

label = TkLabel.new(:relief=>:raised, :width=>10) \
               .pack(:side=>:bottom, :fill=>:both)

tick = proc{|aobj|
  cnt = aobj.return_value + 5
  label.text format("%d.%02d", *(cnt.divmod(100)))
  cnt
}

timer = TkTimer.new(50, -1, tick).start(0, proc{ label.text('0.00'); 0 })

TkButton.new(:text=>'Start') {
  command proc{ timer.continue unless timer.running? }
  pack(:side=>:left, :fill=>:both, :expand=>true)
}
TkButton.new(:text=>'Stop') {
  command proc{ timer.stop if timer.running? }
  pack('side'=>'right','fill'=>'both','expand'=>'yes')
}

ev_quit = TkVirtualEvent.new('Control-c', 'Control-q')
Tk.root.bind(ev_quit, proc{Tk.exit}).focus

Tk.mainloop
