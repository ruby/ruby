#
#  tcheckbutton widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class TCheckButton < TkCheckButton
    end
    TCheckbutton = TCheckButton
  end
end

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
