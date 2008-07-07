#
#  tkextlib/bwidget/titleframe.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tk/frame'
require 'tkextlib/bwidget.rb'

module Tk
  module BWidget
    class TitleFrame < TkWindow
    end
  end
end

class Tk::BWidget::TitleFrame
  TkCommandNames = ['TitleFrame'.freeze].freeze
  WidgetClassName = 'TitleFrame'.freeze
  WidgetClassNames[WidgetClassName] = self

  def get_frame(&b)
    win = window(tk_send_without_enc('getframe'))
    win.instance_eval(&b) if b
    win
  end
end
