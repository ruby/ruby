#
#  tscrollbar widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class TScrollbar < TkScrollbar
    end
  end
end

class Tk::Tile::TScrollbar < TkScrollbar
  include Tk::Tile::TileWidget

  if Tk::Tile::USE_TTK_NAMESPACE
    TkCommandNames = ['::ttk::scrollbar'.freeze].freeze
  else
    TkCommandNames = ['::tscrollbar'.freeze].freeze
  end
  WidgetClassName = 'TScrollbar'.freeze
  WidgetClassNames[WidgetClassName] = self
end
