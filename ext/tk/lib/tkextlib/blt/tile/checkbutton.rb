#
#  tkextlib/blt/tile/checkbutton.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tk/checkbutton'
require 'tkextlib/blt/tile.rb'

module Tk::BLT
  module Tile
    class Checkbutton < TkCheckbutton
      TkCommandNames = ['::blt::tile::checkbutton'.freeze].freeze
    end
    CheckButton = Checkbutton
  end
end
