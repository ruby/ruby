#
#  tkextlib/bwidget/label.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tk/label'
require 'tkextlib/bwidget.rb'

module Tk
  module BWidget
    class Label < TkLabel
    end
  end
end

class Tk::BWidget::Label
  TkCommandNames = ['Label'.freeze].freeze
  WidgetClassName = 'Label'.freeze
  WidgetClassNames[WidgetClassName] = self

  def set_focus
    tk_send_without_enc('setfocus')
    self
  end
end
