#
#  tscale & tprogress widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class TScale < TkScale
    end
    Scale = TScale

    class TProgress < TScale
    end
    Progress = TProgress
  end
end

class Tk::Tile::TScale < TkScale
  include Tk::Tile::TileWidget

  if Tk::Tile::USE_TTK_NAMESPACE
    TkCommandNames = ['::ttk::scale'.freeze].freeze
  else
    TkCommandNames = ['::tscale'.freeze].freeze
  end
  WidgetClassName = 'TScale'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.style(*args)
    [self::WidgetClassName, *(args.map!{|a| _get_eval_string(a)})].join('.')
  end
end

class Tk::Tile::TProgress < Tk::Tile::TScale
  include Tk::Tile::TileWidget

  if Tk::Tile::USE_TTK_NAMESPACE
    TkCommandNames = ['::ttk::progress'.freeze].freeze
  else
    TkCommandNames = ['::tprogress'.freeze].freeze
  end
  WidgetClassName = 'TProgress'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.style(*args)
    [self::WidgetClassName, *(args.map!{|a| _get_eval_string(a)})].join('.')
  end
end
