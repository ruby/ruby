#
#  tlabel widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class TLabel < TkLabel
    end
  end
end

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
