#
#  Tile theme engin (tile widget set) support
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# library directory
dir = File.expand_path(__FILE__).sub(/#{File.extname(__FILE__)}$/, '')

# call setup script
require File.join(dir, 'setup.rb')

# load package
# TkPackage.require('tile', '0.4')
TkPackage.require('tile')

# autoload
module Tk
  module Tile
    module TileWidget
      def instate(state, script=nil, &b)
	if script
	  tk_send('instate', state, script)
	elsif b
	  tk_send('instate', state, Proc.new(&b))
	else
	  bool(tk_send('instate', state))
	end
      end

      def state(state=nil)
	if state
	  tk_send('state', state)
	else
	  list(tk_send('state'))
	end
      end
    end


    # library directory
    dir = File.expand_path(__FILE__).sub(/#{File.extname(__FILE__)}$/, '')

    #autoload :TButton,       'tkextlib/tile/tbutton'
    autoload :TButton,       File.join(dir, 'tbutton')

    #autoload :TCheckButton,  'tkextlib/tile/tcheckbutton'
    #autoload :TCheckbutton,  'tkextlib/tile/tcheckbutton'
    autoload :TCheckButton,  File.join(dir, 'tcheckbutton')
    autoload :TCheckbutton,  File.join(dir, 'tcheckbutton')

    #autoload :TLabel,        'tkextlib/tile/tlabel'
    autoload :TLabel,        File.join(dir, 'tlabel')

    #autoload :TMenubutton,   'tkextlib/tile/tmenubutton'
    autoload :TMenubutton,   File.join(dir, 'tmenubutton')

    #autoload :TNotebook,     'tkextlib/tile/tnotebook'
    autoload :TNotebook,     File.join(dir, 'tnotebook')

    #autoload :TRadioButton,  'tkextlib/tile/tradiobutton'
    #autoload :TRadiobutton,  'tkextlib/tile/tradiobutton'
    autoload :TRadioButton,  File.join(dir, 'tradiobutton')
    autoload :TRadiobutton,  File.join(dir, 'tradiobutton')

    #autoload :Style,         'tkextlib/tile/style'
    autoload :Style,         File.join(dir, 'style')
  end
end
