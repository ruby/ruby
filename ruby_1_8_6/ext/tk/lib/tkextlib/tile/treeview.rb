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
  end
end

module Tk::Tile::TreeviewConfig
  include TkItemConfigMethod

  def __item_configinfo_struct(id)
    # maybe need to override
    {:key=>0, :alias=>nil, :db_name=>nil, :db_class=>nil, 
      :default_value=>nil, :current_value=>1}
  end
  private :__item_configinfo_struct

  def __itemconfiginfo_core(tagOrId, slot = nil)
    if TkComm::GET_CONFIGINFO_AS_ARRAY
      if (slot && slot.to_s =~ /^(|latin|ascii|kanji)(#{__item_font_optkeys(tagid(tagOrId)).join('|')})$/)
        fontkey  = $2
        return [slot.to_s, tagfontobj(tagid(tagOrId), fontkey)]
      else
        if slot
          slot = slot.to_s
          case slot
          when /^(#{__tile_specific_item_optkeys(tagid(tagOrId)).join('|')})$/
            begin
              # On tile-0.7.{2-8}, 'state' options has no '-' at its head.
              val = tk_call(*(__item_confinfo_cmd(tagid(tagOrId)) << slot))
            rescue
              # Maybe, 'state' option has '-' in future.
              val = tk_call(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))
            end
            return [slot, val]

          when /^(#{__item_val2ruby_optkeys(tagid(tagOrId)).keys.join('|')})$/
            method = _symbolkey2str(__item_val2ruby_optkeys(tagid(tagOrId)))[slot]
            optval = tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))
            begin
              val = method.call(tagOrId, optval)
            rescue => e
              warn("Warning:: #{e.message} (when #{method}lcall(#{tagOrId.inspect}, #{optval.inspect})") if $DEBUG
              val = optval
            end
            return [slot, val]

          when /^(#{__item_methodcall_optkeys(tagid(tagOrId)).keys.join('|')})$/
            method = _symbolkey2str(__item_methodcall_optkeys(tagid(tagOrId)))[slot]
            return [slot, self.__send__(method, tagOrId)]

          when /^(#{__item_numval_optkeys(tagid(tagOrId)).join('|')})$/
            begin
              val = number(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}")))
            rescue
              val = nil
            end
            return [slot, val]

          when /^(#{__item_numstrval_optkeys(tagid(tagOrId)).join('|')})$/
            val = num_or_str(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}")))
            return [slot, val]

          when /^(#{__item_boolval_optkeys(tagid(tagOrId)).join('|')})$/
            begin
              val = bool(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}")))
            rescue
              val = nil
            end
            return [slot, val]

          when /^(#{__item_listval_optkeys(tagid(tagOrId)).join('|')})$/
            val = simplelist(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}")))
            return [slot, val]

          when /^(#{__item_numlistval_optkeys(tagid(tagOrId)).join('|')})$/
            val = tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))
            if val =~ /^[0-9]/
              return [slot, list(val)]
            else
              return [slot, val]
            end

          when /^(#{__item_strval_optkeys(tagid(tagOrId)).join('|')})$/
            val = tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))
            return [slot, val]

          when /^(#{__item_tkvariable_optkeys(tagid(tagOrId)).join('|')})$/
            val = tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))
            if val.empty?
              return [slot, nil]
            else
              return [slot, TkVarAccess.new(val)]
            end

          else
            val = tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))
            if val.index('{')
              return [slot, tk_split_list(val)]
            else
              return [slot, tk_tcl2ruby(val)]
            end
          end

        else # ! slot
          ret = Hash[*(tk_split_simplelist(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)))), false, false))].to_a.collect{|conf|
            conf[0] = conf[0][1..-1] if conf[0][0] == ?-
            case conf[0]
            when /^(#{__item_val2ruby_optkeys(tagid(tagOrId)).keys.join('|')})$/
              method = _symbolkey2str(__item_val2ruby_optkeys(tagid(tagOrId)))[conf[0]]
              optval = conf[1]
              begin
                val = method.call(tagOrId, optval)
              rescue => e
                warn("Warning:: #{e.message} (when #{method}.call(#{tagOrId.inspect}, #{optval.inspect})") if $DEBUG
                val = optval
              end
              conf[1] = val

            when /^(#{__item_strval_optkeys(tagid(tagOrId)).join('|')})$/
              # do nothing

            when /^(#{__item_numval_optkeys(tagid(tagOrId)).join('|')})$/
              begin
                conf[1] = number(conf[1])
              rescue
                conf[1] = nil
              end

            when /^(#{__item_numstrval_optkeys(tagid(tagOrId)).join('|')})$/
              conf[1] = num_or_str(conf[1])

            when /^(#{__item_boolval_optkeys(tagid(tagOrId)).join('|')})$/
              begin
                conf[1] = bool(conf[1])
              rescue
                conf[1] = nil
              end

            when /^(#{__item_listval_optkeys(tagid(tagOrId)).join('|')})$/
              conf[1] = simplelist(conf[1])

            when /^(#{__item_numlistval_optkeys(tagid(tagOrId)).join('|')})$/
              if conf[1] =~ /^[0-9]/
                conf[1] = list(conf[1])
              end

            when /^(#{__item_tkvariable_optkeys(tagid(tagOrId)).join('|')})$/
              if conf[1].empty?
                conf[1] = nil
              else
                conf[1] = TkVarAccess.new(conf[1])
              end

            else
              if conf[1].index('{')
                conf[1] = tk_split_list(conf[1])
              else
                conf[1] = tk_tcl2ruby(conf[1])
              end
            end

            conf
          }

          __item_font_optkeys(tagid(tagOrId)).each{|optkey|
            optkey = optkey.to_s
            fontconf = ret.assoc(optkey)
            if fontconf
              ret.delete_if{|inf| inf[0] =~ /^(|latin|ascii|kanji)#{optkey}$/}
              fontconf[1] = tagfontobj(tagid(tagOrId), optkey)
              ret.push(fontconf)
            end
          }

          __item_methodcall_optkeys(tagid(tagOrId)).each{|optkey, method|
            ret << [optkey.to_s, self.__send__(method, tagOrId)]
          }

          ret
        end
      end

    else # ! TkComm::GET_CONFIGINFO_AS_ARRAY
      if (slot && slot.to_s =~ /^(|latin|ascii|kanji)(#{__item_font_optkeys(tagid(tagOrId)).join('|')})$/)
        fontkey  = $2
        return {slot.to_s => tagfontobj(tagid(tagOrId), fontkey)}
      else
        if slot
          slot = slot.to_s
          case slot
          when /^(#{__tile_specific_item_optkeys(tagid(tagOrId)).join('|')})$/
            begin
              # On tile-0.7.{2-8}, 'state' option has no '-' at its head.
              val = tk_call(*(__item_confinfo_cmd(tagid(tagOrId)) << slot))
            rescue
              # Maybe, 'state' option has '-' in future.
              val = tk_call(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))
            end
            return {slot => val}

          when /^(#{__item_val2ruby_optkeys(tagid(tagOrId)).keys.join('|')})$/
            method = _symbolkey2str(__item_val2ruby_optkeys(tagid(tagOrId)))[slot]
            optval = tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))
            begin
              val = method.call(tagOrId, optval)
            rescue => e
              warn("Warning:: #{e.message} (when #{method}lcall(#{tagOrId.inspect}, #{optval.inspect})") if $DEBUG
              val = optval
            end
            return {slot => val}

          when /^(#{__item_methodcall_optkeys(tagid(tagOrId)).keys.join('|')})$/
            method = _symbolkey2str(__item_methodcall_optkeys(tagid(tagOrId)))[slot]
            return {slot => self.__send__(method, tagOrId)}

          when /^(#{__item_numval_optkeys(tagid(tagOrId)).join('|')})$/
            begin
              val = number(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}")))
            rescue
              val = nil
            end
            return {slot => val}

          when /^(#{__item_numstrval_optkeys(tagid(tagOrId)).join('|')})$/
            val = num_or_str(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}")))
            return {slot => val}

          when /^(#{__item_boolval_optkeys(tagid(tagOrId)).join('|')})$/
            begin
              val = bool(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}")))
            rescue
              val = nil
            end
            return {slot => val}

          when /^(#{__item_listval_optkeys(tagid(tagOrId)).join('|')})$/
            val = simplelist(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}")))
            return {slot => val}

          when /^(#{__item_numlistval_optkeys(tagid(tagOrId)).join('|')})$/
            val = tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))
            if val =~ /^[0-9]/
              return {slot => list(val)}
            else
              return {slot => val}
            end

          when /^(#{__item_strval_optkeys(tagid(tagOrId)).join('|')})$/
            val = tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))
            return {slot => val}

          when /^(#{__item_tkvariable_optkeys(tagid(tagOrId)).join('|')})$/
            val = tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))
            if val.empty?
              return {slot => nil}
            else
              return {slot => TkVarAccess.new(val)}
            end

          else
            val = tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))
            if val.index('{')
              return {slot => tk_split_list(val)}
            else
              return {slot => tk_tcl2ruby(val)}
            end
          end

        else # ! slot
          ret = {}
          ret = Hash[*(tk_split_simplelist(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)))), false, false))].to_a.collect{|conf|
            conf[0] = conf[0][1..-1] if conf[0][0] == ?-

            optkey = conf[0]
            case optkey
            when /^(#{__item_val2ruby_optkeys(tagid(tagOrId)).keys.join('|')})$/
              method = _symbolkey2str(__item_val2ruby_optkeys(tagid(tagOrId)))[optkey]
              optval = conf[1]
              begin
                val = method.call(tagOrId, optval)
              rescue => e
                warn("Warning:: #{e.message} (when #{method}.call(#{tagOrId.inspect}, #{optval.inspect})") if $DEBUG
                val = optval
              end
              conf[1] = val

            when /^(#{__item_strval_optkeys(tagid(tagOrId)).join('|')})$/
              # do nothing

            when /^(#{__item_numval_optkeys(tagid(tagOrId)).join('|')})$/
              begin
                conf[1] = number(conf[1])
              rescue
                conf[1] = nil
              end

            when /^(#{__item_numstrval_optkeys(tagid(tagOrId)).join('|')})$/
              conf[1] = num_or_str(conf[1])

            when /^(#{__item_boolval_optkeys(tagid(tagOrId)).join('|')})$/
              begin
                conf[1] = bool(conf[1])
              rescue
                conf[1] = nil
              end

            when /^(#{__item_listval_optkeys(tagid(tagOrId)).join('|')})$/
              conf[1] = simplelist(conf[1])

            when /^(#{__item_numlistval_optkeys(tagid(tagOrId)).join('|')})$/
              if conf[1] =~ /^[0-9]/
                conf[1] = list(conf[1])
              end

            when /^(#{__item_tkvariable_optkeys(tagid(tagOrId)).join('|')})$/
              if conf[1].empty?
                conf[1] = nil
              else
                conf[1] = TkVarAccess.new(conf[1])
              end

            else
              if conf[1].index('{')
                return [slot, tk_split_list(conf[1])]
              else
                return [slot, tk_tcl2ruby(conf[1])]
              end
            end

            ret[conf[0]] = conf[1]
          }

          __item_font_optkeys(tagid(tagOrId)).each{|optkey|
            optkey = optkey.to_s
            fontconf = ret[optkey]
            if fontconf.kind_of?(Array)
              ret.delete(optkey)
              ret.delete('latin' << optkey)
              ret.delete('ascii' << optkey)
              ret.delete('kanji' << optkey)
              fontconf[1] = tagfontobj(tagid(tagOrId), optkey)
              ret[optkey] = fontconf
            end
          }

          __item_methodcall_optkeys(tagid(tagOrId)).each{|optkey, method|
            ret[optkey.to_s] = self.__send__(method, tagOrId)
          }

          ret
        end
      end
    end
  end

  ###################

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
    when :tag, 'tag'
      super(id[1])
    when :heading, 'heading'
      super(id[1])
    else
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
    when :tag, 'tag'
      super(id[1])
    when :heading, 'heading'
      super(id[1])
    else
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
    when :tag, 'tag'
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
    else
      []
    end
  end
  private :__item_listval_optkeys

  def __item_val2ruby_optkeys(id)
    case id[0]
    when :item, 'item'
      { 
        'tags'=>proc{|arg_id, val|
          simplelist(val).collect{|tag|
            Tk::Tile::Treeview::Tag.id2obj(self, tag)
          }
        }
      }
    when :column, 'column'
      {}
    when :heading, 'heading'
      {}
    else
      {}
    end
  end
  private :__item_val2ruby_optkeys

  def __tile_specific_item_optkeys(id)
    case id[0]
    when :item, 'item'
      []
    when :column, 'column'
      []
    when :heading, 'heading'
      ['state']  # On tile-0.7.{2-8}, 'state' options has no '-' at its head.
    else
      []
    end
  end
  private :__item_val2ruby_optkeys

  def itemconfiginfo(tagOrId, slot = nil)
    __itemconfiginfo_core(tagOrId, slot)
  end

  def current_itemconfiginfo(tagOrId, slot = nil)
    if TkComm::GET_CONFIGINFO_AS_ARRAY
      if slot
        org_slot = slot
        begin
          conf = __itemconfiginfo_core(tagOrId, slot)
          if ( ! __item_configinfo_struct(tagid(tagOrId))[:alias] \
              || conf.size > __item_configinfo_struct(tagid(tagOrId))[:alias] + 1 )
            return {conf[0] => conf[-1]}
          end
          slot = conf[__item_configinfo_struct(tagid(tagOrId))[:alias]]
        end while(org_slot != slot)
        fail RuntimeError, 
          "there is a configure alias loop about '#{org_slot}'"
      else
        ret = {}
        __itemconfiginfo_core(tagOrId).each{|conf|
          if ( ! __item_configinfo_struct(tagid(tagOrId))[:alias] \
              || conf.size > __item_configinfo_struct(tagid(tagOrId))[:alias] + 1 )
            ret[conf[0]] = conf[-1]
          end
        }
        ret
      end
    else # ! TkComm::GET_CONFIGINFO_AS_ARRAY
      ret = {}
      __itemconfiginfo_core(tagOrId, slot).each{|key, conf|
        ret[key] = conf[-1] if conf.kind_of?(Array)
      }
      ret
    end
  end

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
    if __tile_specific_item_optkeys([:heading, tagOrId]).index(option.to_s)
      begin
        # On tile-0.7.{2-8}, 'state' options has no '-' at its head.
        tk_call(*(__item_cget_cmd([:heading, tagOrId]) << option.to_s))
      rescue
        # Maybe, 'state' option has '-' in future.
        tk_call(*(__item_cget_cmd([:heading, tagOrId]) << "-#{option}"))
      end
    else
      __itemcget([:heading, tagOrId], option)
    end
  end
  def headingconfigure(tagOrId, slot, value=None)
    if slot.kind_of?(Hash)
      slot = _symbolkey2str(slot)
      sp_kv = []
      __tile_specific_item_optkeys([:heading, tagOrId]).each{|k|
        sp_kv << k << _get_eval_string(slot.delete(k)) if slot.has_key?(k)
      }
      tk_call(*(__item_config_cmd([:heading, tagOrId]).concat(sp_kv)))
      tk_call(*(__item_config_cmd([:heading, tagOrId]).concat(hash_kv(slot))))
    elsif __tile_specific_item_optkeys([:heading, tagOrId]).index(slot.to_s)
      begin
        # On tile-0.7.{2-8}, 'state' options has no '-' at its head.
        tk_call(*(__item_cget_cmd([:heading, tagOrId]) << slot.to_s << value))
      rescue
        # Maybe, 'state' option has '-' in future.
        tk_call(*(__item_cget_cmd([:heading, tagOrId]) << "-#{slot}" << value))
      end
    else
      __itemconfigure([:heading, tagOrId], slot, value)
    end
    self
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

  # Treeview Tag
  def tagcget(tagOrId, option)
    __itemcget([:tag, tagOrId], option)
  end
  def tagconfigure(tagOrId, slot, value=None)
    __itemconfigure([:tag, tagOrId], slot, value)
  end
  def tagconfiginfo(tagOrId, slot=nil)
    __itemconfiginfo([:tag, tagOrId], slot)
  end
  def current_tagconfiginfo(tagOrId, slot=nil)
    __current_itemconfiginfo([:tag, tagOrId], slot)
  end
  alias tag_cget tagcget
  alias tag_configure tagconfigure
  alias tag_configinfo tagconfiginfo
  alias current_tag_configinfo current_tagconfiginfo
end

########################

class Tk::Tile::Treeview::Item < TkObject
  ItemID_TBL = TkCore::INTERP.create_table
  TkCore::INTERP.init_ip_env{ Tk::Tile::Treeview::Item::ItemID_TBL.clear }

  def self.id2obj(tree, id)
    tpath = tree.path
    return id unless Tk::Tile::Treeview::Item::ItemID_TBL[tpath]
    (Tk::Tile::Treeview::Item::ItemID_TBL[tpath][id])? \
          Tk::Tile::Treeview::Item::ItemID_TBL[tpath][id]: id
  end

  def self.assign(tree, id)
    tpath = tree.path
    if Tk::Tile::Treeview::Item::ItemID_TBL[tpath] &&
        Tk::Tile::Treeview::Item::ItemID_TBL[tpath][id]
      return Tk::Tile::Treeview::Item::ItemID_TBL[tpath][id]
    end

    obj = self.allocate
    obj.instance_eval{
      @parent = @t = tree
      @tpath = tpath
      @path = @id = id
    }
    ItemID_TBL[tpath] = {} unless ItemID_TBL[tpath]
    Tk::Tile::Treeview::Item::ItemID_TBL[tpath][id] = obj
    obj
  end

  def _insert_item(tree, parent_item, idx, keys={})
    keys = _symbolkey2str(keys)
    id = keys.delete('id')
    if id
      num_or_str(tk_call(tree, 'insert', 
                         parent_item, idx, '-id', id, *hash_kv(keys)))
    else
      num_or_str(tk_call(tree, 'insert', parent_item, idx, *hash_kv(keys)))
    end
  end
  private :_insert_item

  def initialize(tree, parent_item = '', idx = 'end', keys = {})
    if parent_item.kind_of?(Hash)
      keys = parent_item
      idx = 'end'
      parent_item = ''
    elsif idx.kind_of?(Hash)
      keys = idx
      idx = 'end'
    end

    @parent = @t = tree
    @tpath = tree.path
    @path = @id = _insert_item(@t, parent_item, idx, keys)
    ItemID_TBL[@tpath] = {} unless ItemID_TBL[@tpath]
    ItemID_TBL[@tpath][@id] = self
  end
  def id
    @id
  end

  def cget(option)
    @t.itemcget(@id, option)
  end

  def configure(key, value=None)
    @t.itemconfigure(@id, key, value)
    self
  end

  def configinfo(key=nil)
    @t.itemconfiginfo(@id, key)
  end

  def current_configinfo(key=nil)
    @t.current_itemconfiginfo(@id, key)
  end

  def open?
    cget('open')
  end
  def open
    configure('open', true)
    self
  end
  def close
    configure('open', false)
    self
  end

  def bbox(column=None)
    @t.bbox(@id, column)
  end

  def children
    @t.children(@id)
  end
  def set_children(*items)
    @t.set_children(@id, *items)
    self
  end

  def delete
    @t.delete(@id)
    self
  end

  def detach
    @t.detach(@id)
    self
  end

  def exist?
    @t.exist?(@id)
  end

  def focus
    @t.focus_item(@id)
  end

  def index
    @t.index(@id)
  end

  def insert(idx='end', keys={})
    @t.insert(@id, idx, keys)
  end

  def move(parent, idx)
    @t.move(@id, parent, idx)
    self
  end

  def next_item
    @t.next_item(@id)
  end

  def parent_item
    @t.parent_item(@id)
  end

  def prev_item
    @t.prev_item(@id)
  end

  def see
    @t.see(@id)
    self
  end

  def selection_add
    @t.selection_add(@id)
    self
  end

  def selection_remove
    @t.selection_remove(@id)
    self
  end

  def selection_set
    @t.selection_set(@id)
    self
  end

  def selection_toggle
    @t.selection_toggle(@id)
    self
  end

  def get_directory
    @t.get_directory(@id)
  end
  alias get_dictionary get_directory

  def get(col)
    @t.get(@id, col)
  end

  def set(col, value)
    @t.set(@id, col, value)
  end
end

########################

class Tk::Tile::Treeview::Root < Tk::Tile::Treeview::Item
  def self.new(tree, keys = {})
    tpath = tree.path
    if Tk::Tile::Treeview::Item::ItemID_TBL[tpath] &&
        Tk::Tile::Treeview::Item::ItemID_TBL[tpath]['']
      Tk::Tile::Treeview::Item::ItemID_TBL[tpath]['']
    else
      super(tree, keys)
    end
  end

  def initialize(tree, keys = {})
    @parent = @t = tree
    @tpath = tree.path
    @path = @id = ''
    unless Tk::Tile::Treeview::Item::ItemID_TBL[@tpath]
      Tk::Tile::Treeview::Item::ItemID_TBL[@tpath] = {}
    end
    Tk::Tile::Treeview::Item::ItemID_TBL[@tpath][@id] = self
  end
end

########################

class Tk::Tile::Treeview::Tag < TkObject
  include TkTreatTagFont

  TagID_TBL = TkCore::INTERP.create_table
  Tag_ID = ['tile_treeview_tag'.freeze, '00000'.taint].freeze

  TkCore::INTERP.init_ip_env{ Tk::Tile::Treeview::Tag::TagID_TBL.clear }

  def self.id2obj(tree, id)
    tpath = tree.path
    return id unless Tk::Tile::Treeview::Tag::TagID_TBL[tpath]
    (Tk::Tile::Treeview::Tag::TagID_TBL[tpath][id])? \
          Tk::Tile::Treeview::Tag::TagID_TBL[tpath][id]: id
  end

  def initialize(tree, keys=nil)
    @parent = @t = tree
    @tpath = tree.path
    @path = @id = Tag_ID.join(TkCore::INTERP._ip_id_)
    TagID_TBL[@tpath] = {} unless TagID_TBL[@tpath]
    TagID_TBL[@tpath][@id] = self
    Tag_ID[1].succ!
    if keys && keys != None
      tk_call_without_enc(@tpath, 'tag', 'configure', *hash_kv(keys, true))
    end
  end
  def id
    @id
  end

  def bind(seq, *args)
    if TkComm._callback_entry?(args[0]) || !block_given?
      cmd = args.shift
    else
      cmd = Proc.new
    end
    @t.tag_bind(@id, seq, cmd, *args)
    self
  end

  def bind_append(seq, *args)
    if TkComm._callback_entry?(args[0]) || !block_given?
      cmd = args.shift
    else
      cmd = Proc.new
    end
    @t.tag_bind_append(@id, seq, cmd, *args)
    self
  end

  def bind_remove(seq)
    @t.tag_bind_remove(@id, seq)
    self
  end

  def bindinfo(seq=nil)
    @t.tag_bindinfo(@id, seq)
  end

  def cget(option)
    @t.tagcget(@id, option)
  end

  def configure(key, value=None)
    @t.tagconfigure(@id, key, value)
    self
  end

  def configinfo(key=nil)
    @t.tagconfiginfo(@id, key)
  end

  def current_configinfo(key=nil)
    @t.current_tagconfiginfo(@id, key)
  end
end

########################

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

  def __destroy_hook__
    Tk::Tile::Treeview::Item::ItemID_TBL.delete(@path)
    Tk::Tile::Treeview::Tag::ItemID_TBL.delete(@path)
  end

  def self.style(*args)
    [self::WidgetClassName, *(args.map!{|a| _get_eval_string(a)})].join('.')
  end

  def tagid(id)
    if id.kind_of?(Tk::Tile::Treeview::Item) || 
        id.kind_of?(Tk::Tile::Treeview::Tag)
      id.id
    elsif id.kind_of?(Array)
      [id[0], _get_eval_string(id[1])]
    else
      _get_eval_string(id)
    end
  end

  def root
    Tk::Tile::Treeview::Root.new(self)
  end

  def bbox(item, column=None)
    list(tk_send('item', 'bbox', item, column))
  end

  def children(item)
    simplelist(tk_send_without_enc('children', item)).collect{|id|
      Tk::Tile::Treeview::Item.id2obj(self, id)
    }
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

  def focus_item(item = nil)
    if item
      tk_send('focus', item)
      item
    else
      id = tk_send('focus')
      (id.empty?)? nil: Tk::Tile::Treeview::Item.id2obj(self, id)
    end
  end

  def identify(x, y)
    # tile-0.7.2 or previous
    ret = simplelist(tk_send('identify', x, y))
    case ret[0]
    when 'heading', 'separator'
      ret[-1] = num_or_str(ret[-1])
    when 'cell'
      ret[1] = Tk::Tile::Treeview::Item.id2obj(self, ret[1])
      ret[-1] = num_or_str(ret[-1])
    when 'item', 'row'
      ret[1] = Tk::Tile::Treeview::Item.id2obj(self, ret[1])
    end
  end

  def row_identify(x, y)
    id = tk_send('identify', 'row', x, y)
    (id.empty?)? nil: Tk::Tile::Treeview::Item.id2obj(self, id)
  end

  def column_identify(x, y)
    tk_send('identify', 'column', x, y)
  end

  def index(item)
    number(tk_send('index', item))
  end

  # def insert(parent, idx='end', keys={})
  #   keys = _symbolkey2str(keys)
  #   id = keys.delete('id')
  #   if id
  #     num_or_str(tk_send('insert', parent, idx, '-id', id, *hash_kv(keys)))
  #   else
  #     num_or_str(tk_send('insert', parent, idx, *hash_kv(keys)))
  #   end
  # end
  def insert(parent, idx='end', keys={})
    Tk::Tile::Treeview::Item.new(self, parent, idx, keys)
  end

  # def instate(spec, cmd=Proc.new)
  #   tk_send('instate', spec, cmd)
  # end
  # def state(spec=None)
  #   tk_send('state', spec)
  # end

  def move(item, parent, idx)
    tk_send('move', item, parent, idx)
    self
  end

  def next_item(item)
    id = tk_send('next', item)
    (id.empty?)? nil: Tk::Tile::Treeview::Item.id2obj(self, id)
  end

  def parent_item(item)
    if (id = tk_send('parent', item)).empty?
      Tk::Tile::Treeview::Root.new(self)
    else
      Tk::Tile::Treeview::Item.id2obj(self, id)
    end
  end

  def prev_item(item)
    id = tk_send('prev', item)
    (id.empty?)? nil: Tk::Tile::Treeview::Item.id2obj(self, id)
  end

  def see(item)
    tk_send('see', item)
    self
  end

  def selection
    simplelist(tk_send('selection')).collect{|id|
      Tk::Tile::Treeview::Item.id2obj(self, id)
    }
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
  alias get_dictionary get_directory

  def get(item, col)
    tk_send('set', item, col)
  end
  def set(item, col, value)
    tk_send('set', item, col, value)
    self
  end

  def tag_bind(tag, seq, *args)
    if TkComm._callback_entry?(args[0]) || !block_given?
      cmd = args.shift
    else
      cmd = Proc.new
    end
    _bind([@path, 'tag', 'bind', tag], seq, cmd, *args)
    self
  end
  alias tagbind tag_bind

  def tag_bind_append(tag, seq, *args)
    if TkComm._callback_entry?(args[0]) || !block_given?
      cmd = args.shift
    else
      cmd = Proc.new
    end
    _bind_append([@path, 'tag', 'bind', tag], seq, cmd, *args)
    self
  end
  alias tagbind_append tag_bind_append

  def tag_bind_remove(tag, seq)
    _bind_remove([@path, 'tag', 'bind', tag], seq)
    self
  end
  alias tagbind_remove tag_bind_remove

  def tag_bindinfo(tag, context=nil)
    _bindinfo([@path, 'tag', 'bind', tag], context)
  end
  alias tagbindinfo tag_bindinfo
end
