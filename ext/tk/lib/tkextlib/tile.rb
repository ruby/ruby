#
#  Tile theme engin (tile widget set) support
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# library directory
require 'tkextlib/tile/setup.rb'

# load package
# TkPackage.require('tile', '0.4')
TkPackage.require('tile')

# autoload
module Tk
  module Tile
    TkComm::TkExtlibAutoloadModule.unshift(self)

    def self.package_version
      begin
        TkPackage.require('tile')
      rescue
        ''
      end
    end

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

    ######################################

    autoload :TButton,       'tkextlib/tile/tbutton'

    autoload :TCheckButton,  'tkextlib/tile/tcheckbutton'
    autoload :TCheckbutton,  'tkextlib/tile/tcheckbutton'

    autoload :TLabel,        'tkextlib/tile/tlabel'

    autoload :TMenubutton,   'tkextlib/tile/tmenubutton'

    autoload :TNotebook,     'tkextlib/tile/tnotebook'

    autoload :TRadioButton,  'tkextlib/tile/tradiobutton'
    autoload :TRadiobutton,  'tkextlib/tile/tradiobutton'

    autoload :Style,         'tkextlib/tile/style'
  end
end
