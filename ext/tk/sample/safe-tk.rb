#!/usr/bin/env ruby
# This script is a sample of MultiTkIp class

require "multi-tk"

# create slave interpreters
trusted_slave = MultiTkIp.new_slave
safe_slave1   = MultiTkIp.new_safeTk
safe_slave2   = MultiTkIp.new_safeTk('fill'=>:none, 'expand'=>false)
#safe_slave2   = MultiTkIp.new_safeTk('fill'=>:none)
#safe_slave2   = MultiTkIp.new_safeTk('expand'=>false)


cmd = Proc.new{|txt|
  #####################
  ## from TkTimer2.rb
  begin
    root = TkRoot.new(:title=>'timer sample')
  rescue
    # safeTk doesn't have permission to call 'wm' command
  end
  label = TkLabel.new(:parent=>root, :relief=>:raised, :width=>10) \
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
}

# call on the default master interpreter
trusted_slave.eval_proc(cmd, 'trusted')
safe_slave1.eval_proc(cmd, 'safe1')
safe_slave2.eval_proc(cmd, 'safe2')
cmd.call('master')

Tk.mainloop
