#
#  tkextlib/bwidget/buttonbox.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/bwidget.rb'
require 'tkextlib/bwidget/button'

module Tk
  module BWidget
    class ButtonBox < TkWindow
    end
  end
end

class Tk::BWidget::ButtonBox
  TkCommandNames = ['ButtonBox'.freeze].freeze
  WidgetClassName = 'ButtonBox'.freeze
  WidgetClassNames[WidgetClassName] = self

  include TkItemConfigMethod

  def tagid(tagOrId)
    if tagOrId.kind_of?(Tk::BWidget::Button)
      name = tagOrId[:name]
      return index(name) unless name.empty?
    end
    if tagOrId.kind_of?(TkButton)
      return index(tagOrId[:text])
    end
    # index(tagOrId.to_s)
    index(_get_eval_string(tagOrId))
  end

  def add(keys={}, &b)
    win = window(tk_send('add', *hash_kv(keys)))
    win.instance_eval(&b) if b
    win
  end

  def delete(idx)
    tk_send('delete', tagid(idx))
    self
  end

  def index(idx)
    if idx.kind_of?(Tk::BWidget::Button)
      name = idx[:name]
      idx = name unless name.empty?
    end
    if idx.kind_of?(TkButton)
      idx = idx[:text]
    end
    number(tk_send('index', idx.to_s))
  end

  def insert(idx, keys={}, &b)
    win = window(tk_send('insert', tagid(idx), *hash_kv(keys)))
    win.instance_eval(&b) if b
    win
  end

  def invoke(idx)
    tk_send('invoke', tagid(idx))
    self
  end

  def set_focus(idx)
    tk_send('setfocus', tagid(idx))
    self
  end
end
