#
#  tseparator widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class TSeparator < TkWindow
    end
  end
end

class Tk::Tile::TSeparator < TkWindow
  include Tk::Tile::TileWidget

  if Tk::Tile::USE_TTK_NAMESPACE
    TkCommandNames = ['::ttk::separator'.freeze].freeze
  else
    TkCommandNames = ['::tseparator'.freeze].freeze
  end
  WidgetClassName = 'TSeparator'.freeze
  WidgetClassNames[WidgetClassName] = self
end
