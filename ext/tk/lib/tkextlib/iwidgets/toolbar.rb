#
#  tkextlib/iwidgets/toolbar.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/iwidgets.rb'

module Tk
  module Iwidgets
    class Toolbar < Tk::Itk::Widget
    end
  end
end

class Tk::Iwidgets::Toolbar
  TkCommandNames = ['::iwidgets::toolbar'.freeze].freeze
  WidgetClassName = 'Toolbar'.freeze
  WidgetClassNames[WidgetClassName] = self

  ####################################

  include TkItemConfigMethod

  def tagid(tagOrId)
    if tagOrId.kind_of?(Tk::Itk::Component)
      tagOrId.name
    else
      #_get_eval_string(tagOrId)
      tagOrId
    end
  end

  ####################################

  def add(type, tag=nil, keys={})
    if tag.kind_of?(Hash)
      keys = tag
      tag = nil
    end
    unless tag
      tag = Tk::Itk::Component.new(self)
    end
    tk_call(@path, 'add', type, tagid(tag), *hash_kv(keys))
    tag
  end

  def delete(idx1, idx2=nil)
    if idx2
      tk_call(@path, 'delete', index(idx1), index(idx2))
    else
      tk_call(@path, 'delete', index(idx1))
    end
    self
  end

  def index(idx)
    number(tk_call(@path, 'index', tagid(idx)))
  end

  def insert(idx, type, tag=nil, keys={})
    if tag.kind_of?(Hash)
      keys = tag
      tag = nil
    end
    unless tag
      tag = Tk::Itk::Component.new(self)
    end
    tk_call(@path, 'insert', index(idx), type, tagid(tag), *hash_kv(keys))
    tag
  end

  def invoke(idx=nil)
    if idx
      tk_call(@path, 'invoke', index(idx))
    else
      tk_call(@path, 'invoke')
    end
    self
  end

  def show(idx)
    tk_call(@path, 'show', index(idx))
    self
  end
end
