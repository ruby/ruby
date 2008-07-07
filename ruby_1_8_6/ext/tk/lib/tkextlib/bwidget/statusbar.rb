#
#  tkextlib/bwidget/statusbar.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tk/frame'
require 'tkextlib/bwidget.rb'

module Tk
  module BWidget
    class StatusBar < TkWindow
    end
  end
end

class Tk::BWidget::StatusBar
  TkCommandNames = ['StatusBar'.freeze].freeze
  WidgetClassName = 'StatusBar'.freeze
  WidgetClassNames[WidgetClassName] = self

  def __boolval_optkeys
    super() << 'showresize'
  end
  private :__boolval_optkeys

  def add(win, keys={})
    tk_send('add', win, keys)
    self
  end

  def delete(*wins)
    tk_send('delete', *wins)
    self
  end

  def get_frame(&b)
    win = window(tk_send_without_enc('getframe'))
    win.instance_eval(&b) if b
    win
  end

  def items
    list(tk_send('items'))
  end
end
