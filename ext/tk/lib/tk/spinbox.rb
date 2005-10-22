#
#               tk/spinbox.rb - Tk spinbox classes
#                       $Date$
#                       by Yukihiro Matsumoto <matz@caelum.co.jp>
#
require 'tk'
require 'tk/entry'

class TkSpinbox<TkEntry
  TkCommandNames = ['spinbox'.freeze].freeze
  WidgetClassName = 'Spinbox'.freeze
  WidgetClassNames[WidgetClassName] = self

  class SpinCommand < TkValidateCommand
    class ValidateArgs < TkUtil::CallbackSubst
      KEY_TBL = [
        [ ?d, ?s, :direction ], 
        [ ?s, ?e, :current ], 
        [ ?W, ?w, :widget ], 
        nil
      ]

      PROC_TBL = [
        [ ?s, TkComm.method(:string) ], 
        [ ?w, TkComm.method(:window) ], 

        [ ?e, proc{|val|
            #enc = Tk.encoding
            enc = ((Tk.encoding)? Tk.encoding : Tk.encoding_system)
            if enc
              Tk.fromUTF8(TkComm::string(val), enc)
            else
              TkComm::string(val)
            end
          }
        ], 

        nil
      ]

      _setup_subst_table(KEY_TBL, PROC_TBL);

      def self.ret_val(val)
        (val)? '1': '0'
      end
    end

    def self._config_keys
      ['command']
    end
  end

  def __validation_class_list
    super() << SpinCommand
  end

  Tk::ValidateConfigure.__def_validcmd(binding, SpinCommand)

  #def create_self(keys)
  #  tk_call_without_enc('spinbox', @path)
  #  if keys and keys != None
  #    configure(keys)
  #  end
  #end
  #private :create_self

  def __boolval_optkeys
    super() << 'wrap'
  end
  private :__boolval_optkeys

  def __strval_optkeys
    super() << 'buttonbackground' << 'format'
  end
  private :__strval_optkeys

  def __listval_optkeys
    super() << 'values'
  end
  private :__listval_optkeys

  def identify(x, y)
    tk_send_without_enc('identify', x, y)
  end

  def spinup
    tk_send_without_enc('invoke', 'spinup')
    self
  end

  def spindown
    tk_send_without_enc('invoke', 'spindown')
    self
  end

  def set(str)
    _fromUTF8(tk_send_without_enc('set', _get_eval_enc_str(str)))
  end
end
