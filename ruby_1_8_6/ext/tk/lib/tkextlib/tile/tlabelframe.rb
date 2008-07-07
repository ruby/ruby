#
#  tlabelframe widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class TLabelframe < Tk::Tile::TFrame
    end
    Labelframe = TLabelframe
  end
end

class Tk::Tile::TLabelframe < Tk::Tile::TFrame
  include Tk::Tile::TileWidget

  if Tk::Tile::USE_TTK_NAMESPACE
    TkCommandNames = ['::ttk::labelframe'.freeze].freeze
  else
    TkCommandNames = ['::tlabelframe'.freeze].freeze
  end
  WidgetClassName = 'TLabelframe'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.style(*args)
    [self::WidgetClassName, *(args.map!{|a| _get_eval_string(a)})].join('.')
  end
end
