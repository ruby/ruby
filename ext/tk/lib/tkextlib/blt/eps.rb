#
#  tkextlib/blt/eps.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tk/canvas'
require 'tkextlib/blt.rb'

module Tk::BLT
  class EPS < TkcItem
    CItemTypeName = 'eps'.freeze
    CItemTypeToClass[CItemTypeName] = self
  end
end
