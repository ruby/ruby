#
#  tkextlib/iwidgets/datefield.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/iwidgets.rb'

module Tk
  module Iwidgets
    class  Datefield < Tk::Iwidgets::Labeledwidget
    end
  end
end

class Tk::Iwidgets::Datefield
  TkCommandNames = ['::iwidgets::datefield'.freeze].freeze
  WidgetClassName = 'Datefield'.freeze
  WidgetClassNames[WidgetClassName] = self

  def get_string
    tk_call(@path, 'get', '-string')
  end
  alias get get_string

  def get_clicks
    number(tk_call(@path, 'get', '-clicks'))
  end

  def valid?
    bool(tk_call(@path, 'isvalid'))
  end

  def show(date)
    tk_call(@path, 'show', date)
    self
  end
  def show_now
    tk_call(@path, 'show', 'now')
    self
  end
end
