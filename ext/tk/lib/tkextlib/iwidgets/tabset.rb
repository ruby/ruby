#
#  tkextlib/iwidgets/tabset.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/iwidgets.rb'

module Tk
  module Iwidgets
    class Tabset < Tk::Itk::Widget
    end
  end
end

class Tk::Iwidgets::Tabset
  TkCommandNames = ['::iwidgets::tabset'.freeze].freeze
  WidgetClassName = 'Tabset'.freeze
  WidgetClassNames[WidgetClassName] = self

  ####################################

  include TkItemConfigMethod

  def __item_cget_cmd(id)
    [self.path, 'tabcget', id]
  end
  private :__item_cget_cmd

  def __item_config_cmd(id)
    [self.path, 'tabconfigure', id]
  end
  private :__item_config_cmd

  def tagid(tagOrId)
    if tagOrId.kind_of?(Tk::Itk::Component)
      tagOrId.name
    else
      #_get_eval_string(tagOrId)
      tagOrId
    end
  end

  alias tabcget itemcget
  alias tabconfigure itemconfigure
  alias tabconfiginfo itemconfiginfo
  alias current_tabconfiginfo current_itemconfiginfo

  private :itemcget, :itemconfigure
  private :itemconfiginfo, :current_itemconfiginfo

  ####################################

  def add(keys={})
    window(tk_call(@path, 'add', *hash_kv(keys)))
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

  def insert(idx, keys={})
    window(tk_call(@path, 'insert', index(idx), *hash_kv(keys)))
  end

  def next
    tk_call(@path, 'next')
    self
  end

  def prev
    tk_call(@path, 'prev')
    self
  end

  def select(idx)
    tk_call(@path, 'select', index(idx))
    self
  end
end
