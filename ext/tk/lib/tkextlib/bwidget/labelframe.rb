#
#  tkextlib/bwidget/labelframe.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tk/frame'
require 'tkextlib/bwidget.rb'

module Tk
  module BWidget
    class LabelFrame < TkWindow
    end
  end
end

class Tk::BWidget::LabelFrame
  TkCommandNames = ['LabelFrame'.freeze].freeze
  WidgetClassName = 'LabelFrame'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.align(*args)
    tk_call('LabelFrame::align', *args)
  end
  def get_frame(&b)
    win = window(tk_send_without_enc('getframe'))
    win.instance_eval(&b) if b
    win
  end
end
