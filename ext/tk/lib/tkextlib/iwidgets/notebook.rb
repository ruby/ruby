#
#  tkextlib/iwidgets/notebook.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/iwidgets.rb'

module Tk
  module Iwidgets
    class Notebook < Tk::Itk::Widget
    end
  end
end

class Tk::Iwidgets::Notebook
  TkCommandNames = ['::iwidgets::notebook'.freeze].freeze
  WidgetClassName = 'Notebook'.freeze
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

  alias pagecget itemcget
  alias pageconfigure itemconfigure
  alias pageconfiginfo itemconfiginfo
  alias current_pageconfiginfo current_itemconfiginfo

  private :itemcget, :itemconfigure
  private :itemconfiginfo, :current_itemconfiginfo

  ####################################

  def add(keys={})
    window(tk_call(@path, 'add', *hash_kv(keys)))
  end

  def child_site_list
    list(tk_call(@path, 'childsite'))
  end

  def child_site(idx)
    if (new_idx = self.index(idx)) < 0
      new_idx = tagid(idx)
    end
    window(tk_call(@path, 'childsite', new_idx))
  end

  def delete(idx1, idx2=nil)
    if (new_idx1 = self.index(idx1)) < 0
      new_idx1 = tagid(idx1)
    end
    if idx2
      if (new_idx2 = self.index(idx2)) < 0
        new_idx2 = tagid(idx2)
      end
      tk_call(@path, 'delete', new_idx1, new_idx2)
    else
      tk_call(@path, 'delete', new_idx1)
    end
    self
  end

  def index(idx)
    number(tk_call(@path, 'index', tagid(idx)))
  end

  def insert(idx, keys={})
    if (new_idx = self.index(idx)) < 0
      new_idx = tagid(idx)
    end
    window(tk_call(@path, 'insert', new_idx, *hash_kv(keys)))
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
    if (new_idx = self.index(idx)) < 0
      new_idx = tagid(idx)
    end
    tk_call(@path, 'select', new_idx)
    self
  end

  def scrollcommand(cmd=Proc.new)
    configure_cmd 'scrollcommand', cmd
    self
  end
  alias xscrollcommand scrollcommand
  alias yscrollcommand scrollcommand

  def xscrollbar(bar=nil)
    if bar
      @scrollbar = bar
      @scrollbar.orient 'horizontal'
      self.scrollcommand {|*arg| @scrollbar.set(*arg)}
      @scrollbar.command {|*arg| self.xview(*arg)}
      Tk.update  # avoid scrollbar trouble
    end
    @scrollbar
  end
  def yscrollbar(bar=nil)
    if bar
      @scrollbar = bar
      @scrollbar.orient 'vertical'
      self.scrollcommand {|*arg| @scrollbar.set(*arg)}
      @scrollbar.command {|*arg| self.yview(*arg)}
      Tk.update  # avoid scrollbar trouble
    end
    @scrollbar
  end
  alias scrollbar yscrollbar

  def view(*index)
    if index.size == 0
      window(tk_send_without_enc('view'))
    else
      tk_send_without_enc('view', *index)
      self
    end
  end
  alias xview view
  alias yview view

  def view_moveto(*index)
    view('moveto', *index)
  end
  alias xview_moveto view_moveto
  alias yview_moveto view_moveto
  def view_scroll(*index)
    view('scroll', *index)
  end
  alias xview_scroll view_scroll
  alias yview_scroll view_scroll
end
