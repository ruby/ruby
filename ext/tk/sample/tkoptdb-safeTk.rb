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
MultiTkIp.new_safeTk{
  ent.each{|pat, val| TkOptionDB.add(pat, val)}
  load file
}
# Tk.mainloop is ignored on the slave-IP

Tk.mainloop
