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
    Menubutton = TMenubutton
  end
end

class Tk::Tile::TMenubutton < TkMenubutton
  include Tk::Tile::TileWidget

  if Tk::Tile::USE_TTK_NAMESPACE
    TkCommandNames = ['::ttk::menubutton'.freeze].freeze
  else
    TkCommandNames = ['::tmenubutton'.freeze].freeze
  end
  WidgetClassName = 'TMenubutton'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.style(*args)
    [self::WidgetClassName, *(args.map!{|a| _get_eval_string(a)})].join('.')
  end
end
