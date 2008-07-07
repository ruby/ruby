#
#  tentry widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class TEntry < TkEntry
    end
    Entry = TEntry
  end
end

class Tk::Tile::TEntry < TkEntry
  include Tk::Tile::TileWidget

  if Tk::Tile::USE_TTK_NAMESPACE
    TkCommandNames = ['::ttk::entry'.freeze].freeze
  else
    TkCommandNames = ['::tentry'.freeze].freeze
  end
  WidgetClassName = 'TEntry'.freeze
  WidgetClassNames[WidgetClassName] = self

  def __boolval_optkeys
    super() << 'exportselection'
  end
  private :__boolval_optkeys

  def __strval_optkeys
    super() << 'show'
  end
  private :__strval_optkeys

  def self.style(*args)
    [self::WidgetClassName, *(args.map!{|a| _get_eval_string(a)})].join('.')
  end
end
