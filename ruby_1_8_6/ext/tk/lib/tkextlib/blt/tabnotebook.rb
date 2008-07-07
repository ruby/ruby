#
#  tkextlib/blt/tabnotebook.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/blt.rb'
require 'tkextlib/blt/tabset.rb'

module Tk::BLT
  class Tabnotebook < Tabset
    TkCommandNames = ['::blt::tabnotebook'.freeze].freeze
    WidgetClassName = 'Tabnotebook'.freeze
    WidgetClassNames[WidgetClassName] = self

    def get_tab(index)
      Tk::BLT::Tabset::Tab.id2obj(tk_send_without_enc('id', tagindex(index)))
    end
    alias get_id get_tab
  end
end
