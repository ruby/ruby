#
#  tkextlib/bwidget/labelentry.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tk/entry'
require 'tkextlib/bwidget.rb'
require 'tkextlib/bwidget/labelframe'
require 'tkextlib/bwidget/entry'

module Tk
  module BWidget
    class LabelEntry < TkEntry
    end
  end
end

class Tk::BWidget::LabelEntry
  include Scrollable

  TkCommandNames = ['LabelEntry'.freeze].freeze
  WidgetClassName = 'LabelEntry'.freeze
  WidgetClassNames[WidgetClassName] = self

  #def entrybind(*args)
  #  _bind([path, 'bind'], *args)
  #  self
  #end
  def entrybind(context, *args)
    # if args[0].kind_of?(Proc) || args[0].kind_of?(Method)
    if TkComm._callback_entry?(args[0])
      cmd = args.shift
    else
      cmd = Proc.new
    end
    _bind([path, 'bind'], context, cmd, *args)
    self
  end

  #def entrybind_append(*args)
  #  _bind_append([path, 'bind'], *args)
  #  self
  #end
  def entrybind_append(context, *args)
    #if args[0].kind_of?(Proc) || args[0].kind_of?(Method)
    if TkComm._callback_entry?(args[0])
      cmd = args.shift
    else
      cmd = Proc.new
    end
    _bind_append([path, 'bind'], context, cmd, *args)
    self
  end

  def entrybind_remove(*args)
    _bind_remove([path, 'bind'], *args)
    self
  end

  def entrybindinfo(*args)
    _bindinfo([path, 'bind'], *args)
    self
  end
end
