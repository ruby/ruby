#
#  tkextlib/blt/table.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tk/itemconfig.rb'
require 'tkextlib/blt.rb'

module Tk::BLT
  module Table
    include Tk
    extend Tk
    extend TkItemConfigMethod

    TkCommandNames = ['::blt::table'.freeze].freeze

    module TableContainer
      def blt_table_add(*args)
        Tk::BLT::Table.add(@path, *args)
        self
      end

      def blt_table_arrange()
        Tk::BLT::Table.arrange(@path)
        self
      end

      def blt_table_cget(*args)
        Tk::BLT::Table.cget(@path, *args)
      end

      def blt_table_configure(*args)
        Tk::BLT::Table.configure(@path, *args)
        self
      end

      def blt_table_configinfo(*args)
        Tk::BLT::Table.configinfo(@path, *args)
      end

      def blt_table_current_configinfo(*args)
        Tk::BLT::Table.current_configinfo(@path, *args)
      end

      def blt_table_locate(x, y)
        Tk::BLT::Table.locate(@path, x, y)
      end

      def blt_table_delete(*args)
        Tk::BLT::Table.delete(@path, *args)
        self
      end

      def blt_table_extents(item)
        Tk::BLT::Table.extents(@path, item)
      end

      def blt_table_insert(*args)
        Tk::BLT::Table.insert(@path, *args)
        self
      end

      def blt_table_insert_before(*args)
        Tk::BLT::Table.insert_before(@path, *args)
        self
      end

      def blt_table_insert_after(*args)
        Tk::BLT::Table.insert_after(@path, *args)
        self
      end

      def blt_table_join(first, last)
        Tk::BLT::Table.join(@path, first, last)
        self
      end

      def blt_table_save()
        Tk::BLT::Table.save(@path)
      end

      def blt_table_search(*args)
        Tk::BLT::Table.search(@path, *args)
      end

      def blt_table_split(*args)
        Tk::BLT::Table.split(@path, *args)
        self
      end

      def blt_table_itemcget(*args)
        Tk::BLT::Table.itemcget(@path, *args)
      end

      def blt_table_itemconfigure(*args)
        Tk::BLT::Table.itemconfigure(@path, *args)
        self
      end

      def blt_table_itemconfiginfo(*args)
        Tk::BLT::Table.itemconfiginfo(@path, *args)
      end

      def blt_table_current_itemconfiginfo(*args)
        Tk::BLT::Table.current_itemconfiginfo(@path, *args)
      end

      def blt_table_iteminfo(item)
        Tk::BLT::Table.iteminfo(@path, item)
      end
    end
  end
end


############################################
class << Tk::BLT::Table
  def __item_cget_cmd(id) # id := [ container, item ]
    ['::blt::table', 'cget', id[0].path, id[1]]
  end
  private :__item_cget_cmd

  def __item_config_cmd(id) # id := [ container, item, ... ]
    container, *items = id
    ['::blt::table', 'configure', container.path, *items]
  end
  private :__item_config_cmd

  def __item_pathname(id)
    id[0].path + ';'
  end
  private :__item_pathname

  alias __itemcget itemcget
  alias __itemconfigure itemconfigure
  alias __itemconfiginfo itemconfiginfo
  alias __current_itemconfiginfo current_itemconfiginfo

  private :__itemcget, :__itemconfigure
  private :__itemconfiginfo, :__current_itemconfiginfo

  def tagid(tag)
    if tag.kind_of?(Array)
      case tag[0]
      when Integer
        # [row, col]
        tag.join(',')
      when :c, :C, 'c', 'C', :r, :R, 'r', 'R'
        # c0 or r1 or C*, and so on
        tag.collect{|elem| elem.to_s}.join('')
      else
        tag
      end
    elsif tag.kind_of?(TkWindow)
      _epath(tag)
    else
      tag
    end
  end

  def tagid2obj(tagid)
    tagid
  end

  ############################################

  def cget(container, option)
    __itemcget([container], option)
  end

  def configure(container, *args)
    __itemconfigure([container], *args)
  end

  def configinfo(container, *args)
    __itemconfiginfo([container], *args)
  end

  def current_configinfo(container, *args)
    __current_itemconfiginfo([container], *args)
  end

  def itemcget(container, item, option)
    __itemcget([container, tagid(item)], option)
  end

  def itemconfigure(container, *args)
    if args[-1].kind_of?(Hash)
      # container, item, item, ... , hash_optkeys
      keys = args.pop
      id = [container]
      args.each{|item| id << tagid(item)}
      __itemconfigure(id, keys)
    else
      # container, item, item, ... , option, value
      val = args.pop
      opt = args.pop
      id = [container]
      args.each{|item| id << tagid(item)}
      __itemconfigure(id, opt, val)
    end
  end

  def itemconfiginfo(container, *args)
    slot = args[-1]
    if slot.kind_of?(String) || slot.kind_of?(Symbol)
      slot = slot.to_s
      if slot[0] == ?. || slot =~ /^\d+,\d+$/ || slot =~ /^(c|C|r|R)(\*|\d+)/
        #   widget     ||    row,col          ||    Ci or Ri
        slot = nil
      else
        # option
        slot = args.pop
      end
    else
      slot = nil
    end

    id = [container]
    args.each{|item| id << tagid(item)}
    __itemconfiginfo(id, slot)
  end

  def info(container)
    ret = {}
    inf = list(tk_call('::blt::table', 'info', container))
    until inf.empty?
      opt = inf.slice!(0..1)
      ret[opt[1..-1]] = opt[1]
    end
    ret
  end

  def iteminfo(container, item)
    ret = {}
    inf = list(tk_call('::blt::table', 'info', container, tagid(item)))
    until inf.empty?
      opt = inf.slice!(0..1)
      ret[opt[1..-1]] = opt[1]
    end
    ret
  end

  ############################################

  def create_container(container)
    tk_call('::blt::table', container)
    begin
      class << container
        include Tk::BLT::TABLE::TableContainer
      end
    rescue
      warn('fail to include TableContainer methods (frozen object?)')
    end
    container
  end

  def add(container, win=nil, *args)
    if win
      tk_call('::blt::table', container, _epath(win), *args)
    else
      tk_call('::blt::table', container)
    end
  end

  def arrange(container)
    tk_call('::blt::table', 'arrange', container)
  end

  def delete(container, *args)
    tk_call('::blt::table', 'delete', container, *args)
  end

  def extents(container, item)
    ret = []
    inf = list(tk_call('::blt::table', 'extents', container, item))
    ret << inf.slice!(0..4) until inf.empty?
    ret
  end

  def forget(*wins)
    wins = wins.collect{|win| _epath(win)}
    tk_call('::blt::table', 'forget', *wins)
  end

  def insert(container, *args)
    tk_call('::blt::table', 'insert', container, *args)
  end

  def insert_before(container, *args)
    tk_call('::blt::table', 'insert', container, '-before', *args)
  end

  def insert_after(container, *args)
    tk_call('::blt::table', 'insert', container, '-after', *args)
  end

  def join(container, first, last)
    tk_call('::blt::table', 'join', container, first, last)
  end

  def locate(container, x, y)
    tk_call('::blt::table', 'locate', container, x, y)
  end

  def containers(arg={})
    list(tk_call('::blt::table', 'containers', *hash_kv(arg)))
  end

  def containers_pattern(pat)
    list(tk_call('::blt::table', 'containers', '-pattern', pat))
  end

  def containers_slave(win)
    list(tk_call('::blt::table', 'containers', '-slave', win))
  end

  def save(container)
    tk_call('::blt::table', 'save', container)
  end

  def search(container, keys={})
    list(tk_call('::blt::table', 'containers', *hash_kv(keys)))
  end

  def split(container, *args)
    tk_call('::blt::table', 'split', container, *args)
  end
end
