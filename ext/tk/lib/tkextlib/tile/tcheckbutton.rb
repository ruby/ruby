#
#  tcheckbutton widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script  --  <libdir>/tkextlib/tile.rb
require(File.dirname(File.expand_path(__FILE__)) + '.rb')

class Tk::Tile::TCheckButton < TkCheckButton
  include Tk::Tile::TileWidget

  TkCommandNames = ['tcheckbutton'.freeze].freeze
  WidgetClassName = 'TCheckbutton'.freeze
  WidgetClassNames[WidgetClassName] = self

  def create_self(keys)
    if keys and keys != None
      tk_call_without_enc('tcheckbutton', @path, *hash_kv(keys, true))
    else
      tk_call_without_enc('tcheckbutton', @path)
    end
  end
  private :create_self
end
module Tk
  module Tile
    TCheckbutton = TCheckButton
  end
end
