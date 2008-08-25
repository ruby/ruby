#
#  tbutton widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class TButton < Tk::Button
    end
    Button = TButton
  end
end

Tk.__set_toplevel_aliases__(:Ttk, Tk::Tile::Button, :TkButton)


class Tk::Tile::TButton < Tk::Button
  include Tk::Tile::TileWidget

  if Tk::Tile::USE_TTK_NAMESPACE
    TkCommandNames = ['::ttk::button'.freeze].freeze
  else
    TkCommandNames = ['::tbutton'.freeze].freeze
  end
  WidgetClassName = 'TButton'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.style(*args)
    [self::WidgetClassName, *(args.map!{|a| _get_eval_string(a)})].join('.')
  end
end
