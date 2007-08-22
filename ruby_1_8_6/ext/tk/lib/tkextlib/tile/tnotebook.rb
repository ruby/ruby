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
    Notebook = TNotebook
  end
end

class Tk::Tile::TNotebook < TkWindow
  ################################
  include TkItemConfigMethod
  
  def __item_cget_cmd(id)
    [self.path, 'tab', id]
  end
  private :__item_cget_cmd

  def __item_config_cmd(id)
    [self.path, 'tab', id]
  end
  private :__item_config_cmd

  def __item_listval_optkeys(id)
    []
  end
  private :__item_listval_optkeys

  def __item_methodcall_optkeys(id)  # { key=>method, ... }
    {}
  end
  private :__item_methodcall_optkeys

  #alias tabcget itemcget
  alias tabconfigure itemconfigure
  alias tabconfiginfo itemconfiginfo
  alias current_tabconfiginfo current_itemconfiginfo

  def tabcget(tagOrId, option)
    tabconfigure(tagOrId, option)[-1]
  end
  ################################

  include Tk::Tile::TileWidget

  if Tk::Tile::USE_TTK_NAMESPACE
    TkCommandNames = ['::ttk::notebook'.freeze].freeze
  else
    TkCommandNames = ['::tnotebook'.freeze].freeze
  end
  WidgetClassName = 'TNotebook'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.style(*args)
    [self::WidgetClassName, *(args.map!{|a| _get_eval_string(a)})].join('.')
  end

  def enable_traversal()
    if Tk::Tile::TILE_SPEC_VERSION_ID < 5
      tk_call_without_enc('::tile::enableNotebookTraversal', @path)
    elsif Tk::Tile::TILE_SPEC_VERSION_ID < 7
      tk_call_without_enc('::tile::notebook::enableTraversal', @path)
    else
      tk_call_without_enc('::ttk::notebook::enableTraversal', @path)
    end
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

  def insert(idx, subwin, keys=nil)
    if keys && keys != None
      tk_send('insert', idx, subwin, *hash_kv(keys))
    else
      tk_send('insert', idx, subwin)
    end
    self
  end

  def select(idx)
    tk_send('select', idx)
    self
  end

  def selected
    window(tk_send_without_enc('select'))
  end

  def tabs
    list(tk_send('tabs'))
  end
end
