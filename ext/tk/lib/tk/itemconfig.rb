#
# tk/itemconfig.rb : control item/tag configuration of widget
#
require 'tk'
require 'tkutil'
require 'tk/itemfont.rb'

module TkItemConfigOptkeys
  def __item_numval_optkeys(id)
    []
  end
  private :__item_numval_optkeys

  def __item_numstrval_optkeys(id)
    []
  end
  private :__item_numstrval_optkeys

  def __item_boolval_optkeys(id)
    []
  end
  private :__item_boolval_optkeys

  def __item_strval_optkeys(id)
    # maybe need to override
    ['text', 'label', 'show', 'data', 'file', 'maskdata', 'maskfile']
  end
  private :__item_strval_optkeys

  def __item_listval_optkeys(id)
    []
  end
  private :__item_listval_optkeys

  def __item_numlistval_optkeys(id)
    # maybe need to override
    ['dash', 'activedash', 'disableddash']
  end
  private :__item_numlistval_optkeys

  def __item_methodcall_optkeys(id)  # { key=>method, ... }
    # maybe need to override
    # {'coords'=>'coords'}
    {}
  end
  private :__item_methodcall_optkeys

  ################################################

  def __item_keyonly_optkeys(id)  # { def_key=>(undef_key|nil), ... }
    # maybe need to override
    {}
  end
  private :__item_keyonly_optkeys


  def __conv_item_keyonly_opts(id, keys)
    return keys unless keys.kind_of?(Hash)
    keyonly = __item_keyonly_optkeys(id)
    keys2 = {}
    keys.each{|k, v|
      optkey = keyonly.find{|kk,vv| kk.to_s == k.to_s}
      if optkey
        defkey, undefkey = optkey
        if v
          keys2[defkey.to_s] = None
        else
          keys2[undefkey.to_s] = None
        end
      else
        keys2[k.to_s] = v
      end
    }
    keys2
  end

  def itemconfig_hash_kv(id, keys, enc_mode = nil, conf = nil)
    hash_kv(__conv_item_keyonly_opts(id, keys), enc_mode, conf)
  end
end

module TkItemConfigMethod
  include TkUtil
  include TkTreatItemFont
  include TkItemConfigOptkeys

  def __item_cget_cmd(id)
    # maybe need to override
    [self.path, 'itemcget', id]
  end
  private :__item_cget_cmd

  def __item_config_cmd(id)
    # maybe need to override
    [self.path, 'itemconfigure', id]
  end
  private :__item_config_cmd

  def __item_confinfo_cmd(id)
    # maybe need to override
    __item_config_cmd(id)
  end
  private :__item_confinfo_cmd

  def __item_configinfo_struct(id)
    # maybe need to override
    {:key=>0, :alias=>1, :db_name=>1, :db_class=>2, 
      :default_value=>3, :current_value=>4}
  end
  private :__item_configinfo_struct

  ################################################

  def tagid(tagOrId)
    # maybe need to override
    tagOrId
  end

  ################################################

  def itemcget(tagOrId, option)
    option = option.to_s

    if ( method = _symbolkey2str(__item_methodcall_optkeys(tagid(tagOrId)))[option] )
      return self.__send__(method, tagOrId)
    end

    case option
    when /^(#{__item_numval_optkeys(tagid(tagOrId)).join('|')})$/
      begin
        number(tk_call_without_enc(*(__item_cget_cmd(tagid(tagOrId)) << "-#{option}")))
      rescue
        nil
      end

    when /^(#{__item_numstrval_optkeys(tagid(tagOrId)).join('|')})$/
      num_or_str(tk_call_without_enc(*(__item_cget_cmd(tagid(tagOrId)) << "-#{option}")))

    when /^(#{__item_boolval_optkeys(tagid(tagOrId)).join('|')})$/
      begin
        bool(tk_call_without_enc(*(__item_cget_cmd(tagid(tagOrId)) << "-#{option}")))
      rescue
        nil
      end

    when /^(#{__item_listval_optkeys(tagid(tagOrId)).join('|')})$/
      simplelist(tk_call_without_enc(*(__item_cget_cmd(tagid(tagOrId)) << "-#{option}")))

    when /^(#{__item_numlistval_optkeys(tagid(tagOrId)).join('|')})$/
      conf = tk_call_without_enc(*(__item_cget_cmd(tagid(tagOrId)) << "-#{option}"))
      if conf =~ /^[0-9]/
        list(conf)
      else
        conf
      end

    when /^(#{__item_strval_optkeys(tagid(tagOrId)).join('|')})$/
      _fromUTF8(tk_call_without_enc(*(__item_cget_cmd(tagid(tagOrId)) << "-#{option}")))

    when /^(|latin|ascii|kanji)(#{__item_font_optkeys(tagid(tagOrId)).join('|')})$/
      fontcode = $1
      fontkey  = $2
      fnt = tk_tcl2ruby(tk_call_without_enc(*(__item_cget_cmd(tagid(tagOrId)) << "-#{fontkey}")), true)
      unless fnt.kind_of?(TkFont)
        fnt = tagfontobj(tagid(tagOrId), fontkey)
      end
      if fontcode == 'kanji' && JAPANIZED_TK && TK_VERSION =~ /^4\.*/
        # obsolete; just for compatibility
        fnt.kanji_font
      else
        fnt
      end
    else
      tk_tcl2ruby(tk_call_without_enc(*(__item_cget_cmd(tagid(tagOrId)) << "-#{option}")), true)
    end
  end

  def itemconfigure(tagOrId, slot, value=None)
    if slot.kind_of? Hash
      slot = _symbolkey2str(slot)

      __item_methodcall_optkeys(tagid(tagOrId)).each{|key, method|
        value = slot.delete(key.to_s)
        self.__send__(method, tagOrId, value) if value
      }

      __item_keyonly_optkeys(tagid(tagOrId)).each{|defkey, undefkey|
        conf = slot.find{|kk, vv| kk == defkey.to_s}
        if conf
          k, v = conf
          if v
            slot[k] = None
          else
            slot[undefkey.to_s] = None if undefkey
            slot.delete(k)
          end
        end
      }

      if (slot.find{|k, v| k =~ /^(|latin|ascii|kanji)(#{__item_font_optkeys(tagid(tagOrId)).join('|')})$/})
        tagfont_configure(tagid(tagOrId), slot)
      elsif slot.size > 0
        tk_call(*(__item_config_cmd(tagid(tagOrId)).concat(hash_kv(slot))))
      end

    else
      slot = slot.to_s
      if ( conf = __item_keyonly_optkeys(tagid(tagOrId)).find{|k, v| k.to_s == slot } )
        defkey, undefkey = conf
        if value
          tk_call(*(__item_config_cmd(tagid(tagOrId)) << "-#{defkey}"))
        elsif undefkey
          tk_call(*(__item_config_cmd(tagid(tagOrId)) << "-#{undefkey}"))
        end
      elsif ( method = _symbolkey2str(__item_methodcall_optkeys(tagid(tagOrId)))[slot] )
        self.__send__(method, tagOrId, value)
      elsif (slot =~ /^(|latin|ascii|kanji)(#{__item_font_optkeys(tagid(tagOrId)).join('|')})$/)
        if value == None
          tagfontobj(tagid(tagOrId), $2)
        else
          tagfont_configure(tagid(tagOrId), {slot=>value})
        end
      else
        tk_call(*(__item_config_cmd(tagid(tagOrId)) << "-#{slot}" << value))
      end
    end
    self
  end

  def itemconfiginfo(tagOrId, slot = nil)
    if TkComm::GET_CONFIGINFO_AS_ARRAY
      if (slot.to_s =~ /^(|latin|ascii|kanji)(#{__item_font_optkeys(tagid(tagOrId)).join('|')})$/)
        fontkey  = $2
        conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{fontkey}"))))
        conf[__item_configinfo_struct(tagid(tagOrId))[:key]] = 
          conf[__item_configinfo_struct(tagid(tagOrId))[:key]][1..-1]
        if ( ! __item_configinfo_struct(tagid(tagOrId))[:alias] \
            || conf.size > __item_configinfo_struct(tagid(tagOrId))[:alias] + 1 )
          conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = tagfontobj(tagid(tagOrId), fontkey)
        elsif ( __item_configinfo_struct(tagid(tagOrId))[:alias] \
               && conf.size == __item_configinfo_struct(tagid(tagOrId))[:alias] + 1 \
               && conf[__item_configinfo_struct(tagid(tagOrId))[:alias]][0] == ?- )
          conf[__item_configinfo_struct(tagid(tagOrId))[:alias]] = 
            conf[__item_configinfo_struct(tagid(tagOrId))[:alias]][1..-1]
        end
        conf
      else
        if slot
          slot = slot.to_s
          case slot
          when /^(#{__item_methodcall_optkeys(tagid(tagOrId)).keys.join('|')})$/
            method = _symbolkey2str(__item_methodcall_optkeys(tagid(tagOrId)))[slot]
            return [slot, '', '', '', self.__send__(method, tagOrId)]

          when /^(#{__item_numval_optkeys(tagid(tagOrId)).join('|')})$/
            conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))

            if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
              begin
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                  number(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
              rescue
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = nil
              end
            end
            if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
              begin
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                  number(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
              rescue
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = nil
              end
            end

          when /^(#{__item_numstrval_optkeys(tagid(tagOrId)).join('|')})$/
            conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))

            if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
              conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                num_or_str(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
            end
            if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
              conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                num_or_str(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
            end

          when /^(#{__item_boolval_optkeys(tagid(tagOrId)).join('|')})$/
            conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))

            if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
              begin
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                  bool(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
              rescue
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = nil
              end
            end
            if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
              begin
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                  bool(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
              rescue
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = nil
              end
            end

          when /^(#{__item_listval_optkeys(tagid(tagOrId)).join('|')})$/
            conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))

            if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
              conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                simplelist(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
            end
            if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
              conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                simplelist(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
            end

          when /^(#{__item_numlistval_optkeys(tagid(tagOrId)).join('|')})$/
            conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))

            if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] =~ /^[0-9]/ )
              conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                list(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
            end
            if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] =~ /^[0-9]/ )
              conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                list(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
            end

          when /^(#{__item_strval_optkeys(tagid(tagOrId)).join('|')})$/
            conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))

          else
            conf = tk_split_list(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))
          end
          conf[__item_configinfo_struct(tagid(tagOrId))[:key]] = 
            conf[__item_configinfo_struct(tagid(tagOrId))[:key]][1..-1]

          if ( __item_configinfo_struct(tagid(tagOrId))[:alias] \
              && conf.size == __item_configinfo_struct(tagid(tagOrId))[:alias] + 1 \
              && conf[__item_configinfo_struct(tagid(tagOrId))[:alias]][0] == ?- )
            conf[__item_configinfo_struct(tagid(tagOrId))[:alias]] = 
              conf[__item_configinfo_struct(tagid(tagOrId))[:alias]][1..-1]
          end

          conf

        else
          ret = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)))))).collect{|conflist|
            conf = tk_split_simplelist(conflist)
            conf[__item_configinfo_struct(tagid(tagOrId))[:key]] = 
              conf[__item_configinfo_struct(tagid(tagOrId))[:key]][1..-1]

            case conf[__item_configinfo_struct(tagid(tagOrId))[:key]]
            when /^(#{__item_strval_optkeys(tagid(tagOrId)).join('|')})$/
              # do nothing

            when /^(#{__item_numval_optkeys(tagid(tagOrId)).join('|')})$/
              if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
                begin
                  conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                    number(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
                rescue
                  conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = nil
                end
              end
              if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
                begin
                  conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                    number(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
                rescue
                  conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = nil
                end
              end

            when /^(#{__item_numstrval_optkeys(tagid(tagOrId)).join('|')})$/
              if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                  num_or_str(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
              end
              if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                  num_or_str(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
              end

            when /^(#{__item_boolval_optkeys(tagid(tagOrId)).join('|')})$/
              if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
                begin
                  conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                    bool(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
                rescue
                  conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = nil
                end
              end
              if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
                begin
                  conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                    bool(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
                rescue
                  conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = nil
                end
              end

            when /^(#{__item_listval_optkeys(tagid(tagOrId)).join('|')})$/
              if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                  simplelist(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
              end
              if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                  simplelist(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
              end

            when /^(#{__item_numlistval_optkeys(tagid(tagOrId)).join('|')})$/
              if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] =~ /^[0-9]/ )
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                  list(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
              end
              if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] =~ /^[0-9]/ )
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                  list(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
              end

            else
              if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
                if conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]].index('{')
                  conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                    tk_split_list(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]]) 
                else
                  conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                    tk_tcl2ruby(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]]) 
                end
              end
              if conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]]
                if conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]].index('{')
                  conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                    tk_split_list(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]]) 
                else
                  conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                    tk_tcl2ruby(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]]) 
                end
              end
            end

            if ( __item_configinfo_struct(tagid(tagOrId))[:alias] \
                && conf.size == __item_configinfo_struct(tagid(tagOrId))[:alias] + 1 \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:alias]][0] == ?- )
              conf[__item_configinfo_struct(tagid(tagOrId))[:alias]] = 
                conf[__item_configinfo_struct(tagid(tagOrId))[:alias]][1..-1]
            end

            conf
          }

          __item_font_optkeys(tagid(tagOrId)).each{|optkey|
            optkey = optkey.to_s
            fontconf = ret.assoc(optkey)
            if fontconf && fontconf.size > 2
              ret.delete_if{|inf| inf[0] =~ /^(|latin|ascii|kanji)#{optkey}$/}
              fontconf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = tagfontobj(tagid(tagOrId), optkey)
              ret.push(fontconf)
            end
          }

          __item_methodcall_optkeys(tagid(tagOrId)).each{|optkey, method|
            ret << [optkey.to_s, '', '', '', self.__send__(method, tagOrId)]
          }

          ret
        end
      end

    else # ! TkComm::GET_CONFIGINFO_AS_ARRAY
      if (slot.to_s =~ /^(|latin|ascii|kanji)(#{__item_font_optkeys(tagid(tagOrId)).join('|')})$/)
        fontkey  = $2
        conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{fontkey}"))))
        conf[__item_configinfo_struct(tagid(tagOrId))[:key]] = 
          conf[__item_configinfo_struct(tagid(tagOrId))[:key]][1..-1]

        if ( ! __item_configinfo_struct(tagid(tagOrId))[:alias] \
            || conf.size > __item_configinfo_struct(tagid(tagOrId))[:alias] + 1 )
          conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = fontobj(tagid(tagOrId), fontkey)
          { conf.shift => conf }
        elsif ( __item_configinfo_struct(tagid(tagOrId))[:alias] \
               && conf.size == __item_configinfo_struct(tagid(tagOrId))[:alias] + 1 )
          if conf[__item_configinfo_struct(tagid(tagOrId))[:alias]][0] == ?-
            conf[__item_configinfo_struct(tagid(tagOrId))[:alias]] = 
              conf[__item_configinfo_struct(tagid(tagOrId))[:alias]][1..-1]
          end
          { conf[0] => conf[1] }
        else
          { conf.shift => conf }
        end
      else
        if slot
          slot = slot.to_s
          case slot
          when /^(#{__item_methodcall_optkeys(tagid(tagOrId)).keys.join('|')})$/
            method = _symbolkey2str(__item_methodcall_optkeys(tagid(tagOrId)))[slot]
            return {slot => ['', '', '', self.__send__(method, tagOrId)]}

          when /^(#{__item_numval_optkeys(tagid(tagOrId)).join('|')})$/
            conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))

            if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
              begin
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                  number(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
              rescue
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = nil
              end
            end
            if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
              begin
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                  number(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
              rescue
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = nil
              end
            end

          when /^(#{__item_numstrval_optkeys(tagid(tagOrId)).join('|')})$/
            conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))

            if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
              conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                num_or_stre(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
            end
            if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
              conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                num_or_str(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
            end

          when /^(#{__item_boolval_optkeys(tagid(tagOrId)).join('|')})$/
            conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))

            if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
              begin
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                  bool(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
              rescue
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = nil
              end
            end
            if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
              begin
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                  bool(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
              rescue
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = nil
              end
            end

          when /^(#{__item_listval_optkeys(tagid(tagOrId)).join('|')})$/
            conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))

            if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
              conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                simplelist(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
            end
            if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
              conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                simplelist(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
            end

          when /^(#{__item_numlistval_optkeys(tagid(tagOrId)).join('|')})$/
            conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))

            if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] =~ /^[0-9]/ )
              conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                list(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
            end
            if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] \
                && conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] =~ /^[0-9]/ )
              conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                list(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
            end

          when /^(#{__item_strval_optkeys(tagid(tagOrId)).join('|')})$/
            conf = tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))

          else
            conf = tk_split_list(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)) << "-#{slot}"))))
          end
          conf[__item_configinfo_struct(tagid(tagOrId))[:key]] = 
            conf[__item_configinfo_struct(tagid(tagOrId))[:key]][1..-1]

          if ( __item_configinfo_struct(tagid(tagOrId))[:alias] \
              && conf.size == __item_configinfo_struct(tagid(tagOrId))[:alias] + 1 )
            if conf[__item_configinfo_struct(tagid(tagOrId))[:alias]][0] == ?-
              conf[__item_configinfo_struct(tagid(tagOrId))[:alias]] = 
                conf[__item_configinfo_struct(tagid(tagOrId))[:alias]][1..-1]
            end
            { conf[0] => conf[1] }
          else
            { conf.shift => conf }
          end

        else
          ret = {}
          tk_split_simplelist(_fromUTF8(tk_call_without_enc(*(__item_confinfo_cmd(tagid(tagOrId)))))).each{|conflist|
            conf = tk_split_simplelist(conflist)
            conf[__item_configinfo_struct(tagid(tagOrId))[:key]] = 
              conf[__item_configinfo_struct(tagid(tagOrId))[:key]][1..-1]

            case conf[__item_configinfo_struct(tagid(tagOrId))[:key]]
            when /^(#{__item_strval_optkeys(tagid(tagOrId)).join('|')})$/
              # do nothing

            when /^(#{__item_numval_optkeys(tagid(tagOrId)).join('|')})$/
              if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
                begin
                  conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                    number(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
                rescue
                  conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = nil
                end
              end
              if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
                begin
                  conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                    number(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
                rescue
                  conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = nil
                end
              end

            when /^(#{__item_numstrval_optkeys(tagid(tagOrId)).join('|')})$/
              if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                  num_or_str(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
              end
              if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                  num_or_str(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
              end

            when /^(#{__item_boolval_optkeys(tagid(tagOrId)).join('|')})$/
              if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
                begin
                  conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                    bool(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
                rescue
                  conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = nil
                end
              end
              if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
                begin
                  conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                    bool(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
                rescue
                  conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = nil
                end
              end

            when /^(#{__item_listval_optkeys(tagid(tagOrId)).join('|')})$/
              if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                  simplelist(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
              end
              if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] )
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                  simplelist(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
              end

            when /^(#{__item_numlistval_optkeys(tagid(tagOrId)).join('|')})$/
              if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] =~ /^[0-9]/ )
                conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                  list(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
              end
              if ( conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] =~ /^[0-9]/ )
                conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                  list(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
              end

            else
              if ( __item_configinfo_struct(tagid(tagOrId))[:default_value] \
                  && conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] )
                if conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]].index('{')
                  conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                    tk_split_list(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]]) 
                else
                  conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]] = 
                    tk_tcl2ruby(conf[__item_configinfo_struct(tagid(tagOrId))[:default_value]])
                end
              end
              if conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]]
                if conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]].index('{')
                  conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                    tk_split_list(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]]) 
                else
                  conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = 
                    tk_tcl2ruby(conf[__item_configinfo_struct(tagid(tagOrId))[:current_value]])
                end
              end
            end

            if ( __item_configinfo_struct(tagid(tagOrId))[:alias] \
                && conf.size == __item_configinfo_struct(tagid(tagOrId))[:alias] + 1 )
              if conf[__item_configinfo_struct(tagid(tagOrId))[:alias]][0] == ?-
                conf[__item_configinfo_struct(tagid(tagOrId))[:alias]] = 
                  conf[__item_configinfo_struct(tagid(tagOrId))[:alias]][1..-1]
              end
              ret[conf[0]] = conf[1]
            else
              ret[conf.shift] = conf
            end
          }

          __item_font_optkeys(tagid(tagOrId)).each{|optkey|
            optkey = optkey.to_s
            fontconf = ret[optkey]
            if fontconf.kind_of?(Array)
              ret.delete(optkey)
              ret.delete('latin' << optkey)
              ret.delete('ascii' << optkey)
              ret.delete('kanji' << optkey)
              fontconf[__item_configinfo_struct(tagid(tagOrId))[:current_value]] = tagfontobj(tagid(tagOrId), optkey)
              ret[optkey] = fontconf
            end
          }

          __item_methodcall_optkeys(tagid(tagOrId)).each{|optkey, method|
            ret[optkey.to_s] = ['', '', '', self.__send__(method, tagOrId)]
          }

          ret
        end
      end
    end
  end

  def current_itemconfiginfo(tagOrId, slot = nil)
    if TkComm::GET_CONFIGINFO_AS_ARRAY
      if slot
        org_slot = slot
        begin
          conf = itemconfiginfo(tagOrId, slot)
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
        itemconfiginfo(tagOrId).each{|conf|
          if ( ! __item_configinfo_struct(tagid(tagOrId))[:alias] \
              || conf.size > __item_configinfo_struct(tagid(tagOrId))[:alias] + 1 )
            ret[conf[0]] = conf[-1]
          end
        }
        ret
      end
    else # ! TkComm::GET_CONFIGINFO_AS_ARRAY
      ret = {}
      itemconfiginfo(slot).each{|key, conf|     
        ret[key] = conf[-1] if conf.kind_of?(Array)
      }
      ret
    end
  end
end
