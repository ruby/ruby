#
#  tkextlib/bwidget/entry.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tk/entry'
require 'tkextlib/bwidget.rb'

module Tk
  module BWidget
    class Entry < TkEntry
    end
  end
end

class Tk::BWidget::Entry
  include Scrollable

  TkCommandNames = ['Entry'.freeze].freeze
  WidgetClassName = 'Entry'.freeze
  WidgetClassNames[WidgetClassName] = self

  def invoke
    tk_send_without_enc('invoke')
    self
  end
end
