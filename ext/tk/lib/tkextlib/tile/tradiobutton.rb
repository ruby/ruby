#
#  tradiobutton widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class TRadioButton < TkRadioButton
    end
    TRadiobutton = TRadioButton
  end
end

class Tk::Tile::TRadioButton < TkRadioButton
  include Tk::Tile::TileWidget

  TkCommandNames = ['tradiobutton'.freeze].freeze
  WidgetClassName = 'TRadiobutton'.freeze
  WidgetClassNames[WidgetClassName] = self

  def create_self(keys)
    if keys and keys != None
      tk_call_without_enc('tradiobutton', @path, *hash_kv(keys, true))
    else
      tk_call_without_enc('tradiobutton', @path)
    end
  end
  private :create_self
end
