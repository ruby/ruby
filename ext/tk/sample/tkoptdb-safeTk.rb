#!/usr/bin/env ruby

require 'multi-tk'

TkMessage.new(:text => <<EOM).pack
This is a sample of the safe-Tk slave interpreter. \
On the slave interpreter, 'tkoptdb.rb' demo is running. 
( Attention:: a safe-Tk interpreter can't read options \
from a file. Options are given by the master interpreter \
in this script. )
The window shown this message is a root widget of \
the default master interpreter. The other window \
is a toplevel widget of the master interpreter, and it \
has a container frame of the safe-Tk slave interpreter. \
You can delete the slave by the button on the toplevel widget.
EOM

if ENV['LANG'] =~ /^ja/
  # read Japanese resource
  ent = TkOptionDB.read_entries(File.expand_path('resource.ja', 
						 File.dirname(__FILE__)),
				'euc-jp')
else
  # read English resource
  ent = TkOptionDB.read_entries(File.expand_path('resource.en', 
						File.dirname(__FILE__)))
end
file = File.expand_path('tkoptdb.rb', File.dirname(__FILE__))

ip = MultiTkIp.new_safeTk{
  # When a block is given to 'new_safeTk' method, 
  # the block is evaluated on $SAFE==4.
  ent.each{|pat, val| Tk.tk_call('option', 'add', pat, val)}
}

=begin
ip.eval_proc{
  # When a block is given to 'eval_proc' method, 
  # the block is evaluated on the IP's current safe level.
  # So, the followings raises exceptions. 
  load file
}
=end

ip.eval_proc(proc{
  # When a Procedure object is given to 'eval_proc' method as an argument, 
  # the proc is evaluated on the proc's binding.
  # So, the followings are evaluated on $SAFE==0
  load file
})

# Tk.mainloop is ignored on the slave-IP

Tk.mainloop
