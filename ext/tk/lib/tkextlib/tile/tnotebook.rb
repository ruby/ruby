#
#  tnotebook widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class TNotebook < TkWindow
    end
  end
end

class Tk::Tile::TNotebook < TkWindow
  ################################
  include TkItemConfigMethod
  
  def __item_cget_cmd(id)
    [self.path, 'tabcget', id]
  end
  private :__item_cget_cmd

  def __item_config_cmd(id)
    [self.path, 'tabconfigure', id]
  end
  private :__item_config_cmd


  def __item_listval_optkeys
    []
  end
  private :__item_listval_optkeys

  def __item_methodcall_optkeys  # { key=>method, ... }
    {}
  end
  private :__item_listval_optkeys

  alias tabcget itemcget
  alias tabconfigure itemconfigure
  alias tabconfiginfo itemconfiginfo
  alias current_tabconfiginfo current_itemconfiginfo
  ################################

  include Tk::Tile::TileWidget

  TkCommandNames = ['tnotebook'.freeze].freeze
  WidgetClassName = 'TNotebook'.freeze
  WidgetClassNames[WidgetClassName] = self

  def create_self(keys)
    if keys and keys != None
      tk_call_without_enc('tnotebook', @path, *hash_kv(keys, true))
    else
      tk_call_without_enc('tnotebook', @path)
    end
  end
  private :create_self

  def enable_traversal()
    tk_call_without_end('tile::enableNotebookTraversal', @path)
    self
  end

  def add(child, keys=nil)
    if keys && keys != None
      tk_send_without_enc('add', _epath(child), *hash_kv(keys))
    else
      tk_send_without_enc('add', _epath(child))
    end
    self
  end

  def forget(idx)
    tk_send('forget', idx)
    self
  end    

  def index(idx)
    number(tk_send('index', idx))
  end

  def select(idx)
    tk_send('select', idx)
    self
  end

  def tabs
    list(tk_send('tabs'))
  end
end
