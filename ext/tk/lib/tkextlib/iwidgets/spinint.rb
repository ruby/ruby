#
#  tkextlib/iwidgets/spinint.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/iwidgets.rb'

module Tk
  module Iwidgets
    class  Spinint < Tk::Iwidgets::Spinner
    end
  end
end

class Tk::Iwidgets::Spinint
  TkCommandNames = ['::iwidgets::spinint'.freeze].freeze
  WidgetClassName = 'Spinint'.freeze
  WidgetClassNames[WidgetClassName] = self
end
