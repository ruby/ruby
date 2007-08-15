#
#  tframe widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class TFrame < TkFrame
    end
    Frame = TFrame
  end
end

class Tk::Tile::TFrame < TkFrame
  include Tk::Tile::TileWidget

  if Tk::Tile::USE_TTK_NAMESPACE
    TkCommandNames = ['::ttk::frame'.freeze].freeze
  else
    TkCommandNames = ['::tframe'.freeze].freeze
  end
  WidgetClassName = 'TFrame'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.style(*args)
    [self::WidgetClassName, *(args.map!{|a| _get_eval_string(a)})].join('.')
  end
end
