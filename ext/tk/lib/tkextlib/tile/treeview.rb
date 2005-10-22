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

    module TreeviewConfig
      include TkItemConfigMethod

      def __item_cget_cmd(id)
        [self.path, id[0], id[1]]
      end
      private :__item_cget_cmd

      def __item_config_cmd(id)
        [self.path, id[0], id[1]]
      end
      private :__item_config_cmd

      def __item_numstrval_optkeys(id)
        case id[0]
        when :item, 'item'
          ['width']
        when :column, 'column'
          super(id[1])
        when :heading, 'heading'
          super(id[1])
        end
      end
      private :__item_numstrval_optkeys

      def __item_strval_optkeys(id)
        case id[0]
        when :item, 'item'
          super(id) + ['id']
        when :column, 'column'
          super(id[1])
        when :heading, 'heading'
          super(id[1])
        end
      end
      private :__item_strval_optkeys

      def __item_boolval_optkeys(id)
        case id[0]
        when :item, 'item'
          ['open']
        when :column, 'column'
          super(id[1])
        when :heading, 'heading'
          super(id[1])
        end
      end
      private :__item_boolval_optkeys

      def __item_listval_optkeys(id)
        case id[0]
        when :item, 'item'
          ['values']
        when :column, 'column'
          []
        when :heading, 'heading'
          []
        end
      end
      private :__item_listval_optkeys

      alias __itemcget itemcget
      alias __itemconfigure itemconfigure
      alias __itemconfiginfo itemconfiginfo
      alias __current_itemconfiginfo current_itemconfiginfo

      private :__itemcget, :__itemconfigure
      private :__itemconfiginfo, :__current_itemconfiginfo

      # Treeview Item
      def itemcget(tagOrId, option)
        __itemcget([:item, tagOrId], option)
      end
      def itemconfigure(tagOrId, slot, value=None)
        __itemconfigure([:item, tagOrId], slot, value)
      end
      def itemconfiginfo(tagOrId, slot=nil)
        __itemconfiginfo([:item, tagOrId], slot)
      end
      def current_itemconfiginfo(tagOrId, slot=nil)
        __current_itemconfiginfo([:item, tagOrId], slot)
      end

      # Treeview Column
      def columncget(tagOrId, option)
        __itemcget([:column, tagOrId], option)
      end
      def columnconfigure(tagOrId, slot, value=None)
        __itemconfigure([:column, tagOrId], slot, value)
      end
      def columnconfiginfo(tagOrId, slot=nil)
        __itemconfiginfo([:column, tagOrId], slot)
      end
      def current_columnconfiginfo(tagOrId, slot=nil)
        __current_itemconfiginfo([:column, tagOrId], slot)
      end
      alias column_cget columncget
      alias column_configure columnconfigure
      alias column_configinfo columnconfiginfo
      alias current_column_configinfo current_columnconfiginfo

      # Treeview Heading
      def headingcget(tagOrId, option)
        __itemcget([:heading, tagOrId], option)
      end
      def headingconfigure(tagOrId, slot, value=None)
        __itemconfigure([:heading, tagOrId], slot, value)
      end
      def headingconfiginfo(tagOrId, slot=nil)
        __itemconfiginfo([:heading, tagOrId], slot)
      end
      def current_headingconfiginfo(tagOrId, slot=nil)
        __current_itemconfiginfo([:heading, tagOrId], slot)
      end
      alias heading_cget headingcget
      alias heading_configure headingconfigure
      alias heading_configinfo headingconfiginfo
      alias current_heading_configinfo current_headingconfiginfo
    end
  end
end

class Tk::Tile::Treeview < TkWindow
  include Tk::Tile::TileWidget
  include Scrollable

  include Tk::Tile::TreeviewConfig

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
    if id.kind_of?(Array)
      [id[0], _get_eval_string(id[1])]
    else
      _get_eval_string(id)
    end
  end

  def children(item)
    simplelist(tk_send_without_enc('children', item))
  end
  def set_children(item, *items)
    tk_send_without_enc('children', item, 
                        array2tk_list(items.flatten, true))
    self
  end

  def delete(*items)
    tk_send_without_enc('delete', array2tk_list(items.flatten, true))
    self
  end

  def detach(*items)
    tk_send_without_enc('detach', array2tk_list(items.flatten, true))
    self
  end

  def exist?(item)
    bool(tk_send_without_enc('exists', _get_eval_enc_str(item)))
  end

  def focus_item(item = None)
    tk_send('focus', item)
  end

  def identify(x, y)
    ret = simplelist(tk_send('identify', x, y))
    case ret[0]
    when 'heading', 'separator', 'cell'
      ret[-1] = num_or_str(ret[-1])
    end
  end

  def index(item)
    number(tk_send('index', item))
  end

  def insert(parent, idx, keys={})
    keys = _symbolkey2str(keys)
    id = keys.delete('id')
    if id
      tk_send('insert', parent, idx, '-id', id, *hash_kv(keys))
    else
      tk_send('insert', parent, idx, *hash_kv(keys))
    end
    self
  end

  def instate(spec, cmd=Proc.new)
    tk_send('instate', spec, cmd)
  end
  def state(spec=None)
    tk_send('state', spec)
  end

  def move(item, parent, idx)
    tk_send('move', item, parent, idx)
    self
  end

  def next(item)
    tk_send('next', item)
  end

  def parent(item)
    tk_send('parent', item)
  end

  def prev(item)
    tk_send('prev', item)
  end

  def see(item)
    tk_send('see', item)
    self
  end

  def selection
    simplelist(tk_send('selection'))
  end
  alias selection_get selection

  def selection_add(*items)
    tk_send('selection', 'add', array2tk_list(items.flatten, true))
    self
  end
  def selection_remove(*items)
    tk_send('selection', 'remove', array2tk_list(items.flatten, true))
    self
  end
  def selection_set(*items)
    tk_send('selection', 'set', array2tk_list(items.flatten, true))
    self
  end
  def selection_toggle(*items)
    tk_send('selection', 'toggle', array2tk_list(items.flatten, true))
    self
  end

  def get_directory(item)
    # tile-0.7+
    ret = []
    lst = simplelist(tk_send('set', item))
    until lst.empty?
      col = lst.shift
      val = lst.shift
      ret << [col, val]
    end
    ret
  end
  def get(item, col)
    tk_send('set', item, col)
  end
  def set(item, col, value)
    tk_send('set', item, col, value)
    self
  end
end
