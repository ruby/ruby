#
#  treeview widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class Treeview < TkWindow
    end

    module TreeviewItemConfig
      include TkItemConfigMethod

      def __item_cget_cmd(id)
        [self.path, 'item', id]
      end
      private :__item_cget_cmd

      def __item_config_cmd(id)
        [self.path, 'item', id]
      end
      private :__item_config_cmd

      def __item_numstrval_optkeys(id)
        ['width']
      end
      private :__item_numstrval_optkeys

      def __item_strval_optkeys(id)
        # maybe need to override
        super(id) + ['id']
      end
      private :__item_strval_optkeys

      def __item_boolval_optkeys(id)
        ['open']
      end
      private :__item_boolval_optkeys

      def __item_listval_optkeys(id)
        ['values']
      end
      private :__item_listval_optkeys
    end

    module TreeviewColumnConfig
      include TkItemConfigMethod

      def __item_cget_cmd(id)
        [self.path, 'column', id]
      end
      private :__item_cget_cmd

      def __item_config_cmd(id)
        [self.path, 'column', id]
      end
      private :__item_config_cmd

      def __item_listval_optkeys(id)
        []
      end
      private :__item_listval_optkeys

      alias columncget itemcget
      alias columnconfigure itemconfigure
      alias columnconfiginfo itemconfiginfo
      alias current_columnconfiginfo current_itemconfiginfo

      private :itemcget, :itemconfigure
      private :itemconfiginfo, :current_itemconfiginfo
    end

    module TreeviewHeadingConfig
      include TkItemConfigMethod

      def __item_cget_cmd(id)
        [self.path, 'heading', id]
      end
      private :__item_cget_cmd

      def __item_config_cmd(id)
        [self.path, 'heading', id]
      end
      private :__item_config_cmd

      def __item_listval_optkeys(id)
        []
      end
      private :__item_listval_optkeys

      alias headingcget itemcget
      alias headingconfigure itemconfigure
      alias headingconfiginfo itemconfiginfo
      alias current_headingconfiginfo current_itemconfiginfo

      private :itemcget, :itemconfigure
      private :itemconfiginfo, :current_itemconfiginfo
    end
  end
end

class Tk::Tile::Treeview < TkWindow
  include Tk::Tile::TileWidget
  include Scrollable

  include Tk::Tile::TreeviewColumnConfig
  include Tk::Tile::TreeviewHeadingConfig
  include Tk::Tile::TreeviewItemConfig

  if Tk::Tile::USE_TTK_NAMESPACE
    TkCommandNames = ['::ttk::treeview'.freeze].freeze
  else
    TkCommandNames = ['::treeview'.freeze].freeze
  end
  WidgetClassName = 'Treeview'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.style(*args)
    [self::WidgetClassName, *(args.map!{|a| _get_eval_string(a)})].join('.')
  end

  def tagid(id)
    _get_eval_string(id)
  end

  def children(item)
    list(tk_send_without_enc('children', item))
  end
  def children=(item, *items)
    tk_send_without_enc('children', item, *items)
    items
  end

  def delete(*items)
    tk_send_without_enc('delete', *items)
    self
  end

  def detach(*items)
    tk_send_without_enc('detach', *items)
    self
  end

  def exist?(item)
    bool(tk_send_without_enc('exists', item))
  end

  def focus_item(item = None)
    tk_send_without_enc('focus', item)
  end

  def identify(x, y)
    tk_send_without_enc('identify', x, y)
  end

  def index(item)
    number(tk_send_without_enc('index', item))
  end

  def insert(parent, idx, keys={})
    keys = _symbolkey2str(keys)
    id = keys.delete('id')
    if id
      tk_send_without_enc('insert', parent, idx, '-id', id, *hash_kv(keys))
    else
      tk_send_without_enc('insert', parent, idx, *hash_kv(keys))
    end
    self
  end

  def move(item, parent, idx)
    tk_send_without_enc('move', item, parent, idx)
    self
  end

  def next(item)
    tk_send_without_enc('next', item)
  end

  def parent(item)
    tk_send_without_enc('parent', item)
  end

  def prev(item)
    tk_send_without_enc('prev', item)
  end

  def see(item)
    tk_send_without_enc('see', item)
    self
  end

  def selection_add(*items)
    tk_send_without_enc('selection', 'add', *items)
    self
  end
  def selection_remove(*items)
    tk_send_without_enc('selection', 'remove', *items)
    self
  end
  def selection_set(*items)
    tk_send_without_enc('selection', 'set', *items)
    self
  end
  def selection_toggle(*items)
    tk_send_without_enc('selection', 'toggle', *items)
    self
  end

  def get(item, col)
    tk_send_without_enc('set', item, col)
  end
  def set(item, col, value)
    tk_send_without_enc('set', item, col, value)
    self
  end
end
