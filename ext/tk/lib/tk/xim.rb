#
# tk/xim.rb : control imput_method
#
require 'tk'

module TkXIM
  include Tk
  extend Tk

  TkCommandNames = ['imconfigure'.freeze].freeze

  def TkXIM.useinputmethods(value = None, window = nil)
    if value == None
      if window
        bool(tk_call_without_enc('tk', 'useinputmethods', 
                                 '-displayof', window))
      else
        bool(tk_call_without_enc('tk', 'useinputmethods'))
      end
    else
      if window
        bool(tk_call_without_enc('tk', 'useinputmethods', 
                                 '-displayof', window, value))
      else
        bool(tk_call_without_enc('tk', 'useinputmethods', value))
      end
    end
  end

  def TkXIM.useinputmethods_displayof(window, value = None)
    TkXIM.useinputmethods(value, window)
  end

  def TkXIM.caret(window, keys=nil)
    if keys
      tk_call_without_enc('tk', 'caret', window, *hash_kv(keys))
      self
    else
      lst = tk_split_list(tk_call_without_enc('tk', 'caret', window))
      info = {}
      while key = lst.shift
        info[key[1..-1]] = lst.shift
      end
      info
    end
  end

  def TkXIM.configure(window, slot, value=None)
    begin
      if /^8\.*/ === Tk::TK_VERSION  && JAPANIZED_TK
        if slot.kind_of? Hash
          tk_call('imconfigure', window, *hash_kv(slot))
        else
          tk_call('imconfigure', window, "-#{slot}", value)
        end
      end
    rescue
    end
  end

  def TkXIM.configinfo(window, slot=nil)
    if TkComm::GET_CONFIGINFOwoRES_AS_ARRAY
      begin
        if /^8\.*/ === Tk::TK_VERSION  && JAPANIZED_TK
          if slot
            conf = tk_split_list(tk_call('imconfigure', window, "-#{slot}"))
            conf[0] = conf[0][1..-1]
            conf
          else
            tk_split_list(tk_call('imconfigure', window)).collect{|conf|
              conf[0] = conf[0][1..-1]
              conf
            }
          end
        else
          []
        end
      rescue
        []
      end
    else # ! TkComm::GET_CONFIGINFOwoRES_AS_ARRAY
      TkXIM.current_configinfo(window, slot)
    end
  end

  def TkXIM.current_configinfo(window, slot=nil)
    begin
      if /^8\.*/ === Tk::TK_VERSION  && JAPANIZED_TK
        if slot
          conf = tk_split_list(tk_call('imconfigure', window, "-#{slot}"))
          { conf[0][1..-1] => conf[1] }
        else
          ret = {}
          tk_split_list(tk_call('imconfigure', window)).each{|conf|
            ret[conf[0][1..-1]] = conf[1]
          }
          ret
        end
      else
        {}
      end
    rescue
      {}
    end
  end

  def useinputmethods(value=None)
    TkXIM.useinputmethods(value, self)
  end

  def caret(keys=nil)
    TkXIM.caret(self, keys=nil)
  end

  def imconfigure(slot, value=None)
    TkXIM.configure(self, slot, value)
  end

  def imconfiginfo(slot=nil)
    TkXIM.configinfo(self, slot)
  end
end
