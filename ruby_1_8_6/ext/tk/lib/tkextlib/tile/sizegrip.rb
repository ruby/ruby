#
#  ttk::sizegrip widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class SizeGrip < TkWindow
    end
  end
end

class Tk::Tile::SizeGrip < TkWindow
  include Tk::Tile::TileWidget

  TkCommandNames = ['::ttk::sizegrip'.freeze].freeze
  WidgetClassName = 'TSizegrip'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.style(*args)
    [self::WidgetClassName, *(args.map!{|a| _get_eval_string(a)})].join('.')
  end
end
