#
#  tmenubutton widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class TMenubutton < TkMenubutton
    end
  end
end

class Tk::Tile::TMenubutton < TkMenubutton
  include Tk::Tile::TileWidget

  TkCommandNames = ['tmenubutton'.freeze].freeze
  WidgetClassName = 'TMenubutton'.freeze
  WidgetClassNames[WidgetClassName] = self

  def create_self(keys)
    if keys and keys != None
      tk_call_without_enc('tmenubutton', @path, *hash_kv(keys, true))
    else
      tk_call_without_enc('tmenubutton', @path)
    end
  end
  private :create_self
end
