#
#  tkextlib/iwidgets/canvasprintbox.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/iwidgets.rb'

module Tk
  module Iwidgets
    class Canvasprintbox < Tk::Itk::Widget
    end
  end
end

class Tk::Iwidgets::Canvasprintbox
  TkCommandNames = ['::iwidgets::canvasprintbox'.freeze].freeze
  WidgetClassName = 'Canvasprintbox'.freeze
  WidgetClassNames[WidgetClassName] = self

  def get_output
    tk_call(@path, 'getoutput')
  end

  def print
    bool(tk_call(@path, 'print'))
  end

  def refresh
    tk_call(@path, 'refresh')
    self
  end

  def set_canvas(win)
    tk_call(@path, 'setcanvas', win)
    self
  end

  def stop
    tk_call(@path, 'stop')
    self
  end
end
