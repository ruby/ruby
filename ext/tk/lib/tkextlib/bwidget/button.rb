#
#  tkextlib/bwidget/button.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tk/button'
require 'tkextlib/bwidget.rb'

module Tk
  module BWidget
    class Button < TkButton
    end
  end
end

class Tk::BWidget::Button
  TkCommandNames = ['Button'.freeze].freeze
  WidgetClassName = 'Button'.freeze
  WidgetClassNames[WidgetClassName] = self
end
