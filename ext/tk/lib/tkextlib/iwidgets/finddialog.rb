#
#  tkextlib/iwidgets/finddialog.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/iwidgets.rb'

module Tk
  module Iwidgets
    class Finddialog < Tk::Iwidgets::Dialogshell
    end
  end
end

class Tk::Iwidgets::Finddialog
  TkCommandNames = ['::iwidgets::finddialog'.freeze].freeze
  WidgetClassName = 'Finddialog'.freeze
  WidgetClassNames[WidgetClassName] = self

  def clear
    tk_call(@path, 'clear')
    self
  end

  def find
    tk_call(@path, 'find')
  end
end
