#
#  tkextlib/bwidget/combobox.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tk/entry'
require 'tkextlib/bwidget.rb'
require 'tkextlib/bwidget/listbox'
require 'tkextlib/bwidget/spinbox'

module Tk
  module BWidget
    class ComboBox < Tk::BWidget::SpinBox
    end
  end
end

class Tk::BWidget::ComboBox
  include Scrollable

  TkCommandNames = ['ComboBox'.freeze].freeze
  WidgetClassName = 'ComboBox'.freeze
  WidgetClassNames[WidgetClassName] = self

  def get_listbox(&b)
    win = window(tk_send_without_enc('getlistbox'))
    win.instance_eval(&b) if b
    win
  end

  def icursor(idx)
    tk_send_without_enc('icursor', idx)
  end

  def post
    tk_send_without_enc('post')
    self
  end

  def unpost
    tk_send_without_enc('unpost')
    self
  end
end
