#
#  tlabel widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script  --  <libdir>/tkextlib/tile.rb
require(File.dirname(File.expand_path(__FILE__)) + '.rb')

class Tk::Tile::TLabel < TkLabel
  include Tk::Tile::TileWidget

  TkCommandNames = ['tlabel'.freeze].freeze
  WidgetClassName = 'TLabel'.freeze
  WidgetClassNames[WidgetClassName] = self

  def create_self(keys)
    if keys and keys != None
      tk_call_without_enc('tlabel', @path, *hash_kv(keys, true))
    else
      tk_call_without_enc('tlabel', @path)
    end
  end
  private :create_self
end
