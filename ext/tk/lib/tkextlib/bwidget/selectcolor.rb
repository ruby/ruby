#
#  tkextlib/bwidget/selectcolor.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/bwidget.rb'
require 'tkextlib/bwidget/messagedlg'

module Tk
  module BWidget
    class SelectColor < Tk::BWidget::MessageDlg
    end
  end
end

class Tk::BWidget::SelectColor
  extend Tk

  TkCommandNames = ['SelectColor'.freeze].freeze
  WidgetClassName = 'SelectColor'.freeze
  WidgetClassNames[WidgetClassName] = self

  def dialog(keys={})
    newkeys = @keys.dup
    newkeys.update(_symbolkey2str(keys))
    tk_call('SelectColor::dialog', @path, *hash_kv(newkeys))
  end

  def menu(*args)
    if args[-1].kind_of?(Hash)
      keys = args.pop
    else
      keys = {}
    end
    place = args.flatten
    newkeys = @keys.dup
    newkeys.update(_symbolkey2str(keys))
    tk_call('SelectColor::menu', @path, place, *hash_kv(newkeys))
  end

  def self.set_color(idx, color)
    tk_call('SelectColor::setcolor', idx, color)
  end
end
