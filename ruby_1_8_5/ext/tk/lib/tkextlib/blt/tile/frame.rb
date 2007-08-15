#
#  tkextlib/blt/tile/frame.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tk/frame'
require 'tkextlib/blt/tile.rb'

module Tk::BLT
  module Tile
    class Frame < TkFrame
      TkCommandNames = ['::blt::tile::frame'.freeze].freeze
    end
  end
end
