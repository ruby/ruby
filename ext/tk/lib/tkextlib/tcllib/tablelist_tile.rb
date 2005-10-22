#
#  tkextlib/tcllib/tablelist_tlie.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
#   * Part of tcllib extension
#   * A multi-column listbox

require 'tk'
require 'tkextlib/tcllib.rb'

# TkPackage.require('tablelist_tile', '4.2')
TkPackage.require('Tablelist_tile')

unless defined? Tk::Tcllib::Tablelist_usingTile
  Tk::Tcllib::Tablelist_usingTile = true
end

requrie 'tkextlib/tcllib/tablelist_core'

module Tk
  module Tcllib
    Tablelist_Tile = Tablelist
    TableList_Tile = Tablelist
  end
end
