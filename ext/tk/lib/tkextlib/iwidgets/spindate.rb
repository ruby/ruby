#
#  tkextlib/iwidgets/spindate.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/iwidgets.rb'

module Tk
  module Iwidgets
    class Spindate < Tk::Itk::Widget
    end
  end
end

class Tk::Iwidgets::Spindate
  TkCommandNames = ['::iwidgets::spindate'.freeze].freeze
  WidgetClassName = 'Spindate'.freeze
  WidgetClassNames[WidgetClassName] = self

  def get_string
    tk_call(@path, 'get', '-string')
  end
  alias get get_string

  def get_clicks
    number(tk_call(@path, 'get', '-clicks'))
  end

  def show(date=None)
    tk_call(@path, 'show', date)
    self
  end
  def show_now
    tk_call(@path, 'show', 'now')
    self
  end
end
