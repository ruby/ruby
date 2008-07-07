#
#  tkextlib/bwidget/scrollableframe.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tk/frame'
require 'tkextlib/bwidget.rb'

module Tk
  module BWidget
    class ScrollableFrame < TkWindow
    end
  end
end

class Tk::BWidget::ScrollableFrame
  include Scrollable

  TkCommandNames = ['ScrollableFrame'.freeze].freeze
  WidgetClassName = 'ScrollableFrame'.freeze
  WidgetClassNames[WidgetClassName] = self

  def get_frame(&b)
    win = window(tk_send_without_enc('getframe'))
    win.instance_eval(&b) if b
    win
  end

  def see(win, vert=None, horiz=None)
    tk_send_without_enc('see', win, vert, horiz)
    self
  end
end
