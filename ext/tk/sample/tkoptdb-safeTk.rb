#!/usr/bin/env ruby

require 'multi-tk'

TkMessage.new(:text => <<EOM).pack
This is a sample of the safe-Tk slave interpreter. \
On the slave interpreter, 'tkoptdb.rb' demo is running. 
The window shown this message is a root widget of \
the default master interpreter. The other window \
is a toplevel widget of the master interpreter, and it \
has a container frame of the safe-Tk slave interpreter. \
You can delete the slave by the button on the toplevel widget.
EOM

file = File.expand_path('tkoptdb.rb', File.dirname(__FILE__))
MultiTkIp.new_safeTk{load file}

# mainloop is started on 'tkoptdb.rb'
