#
# tk/radiobutton.rb : treat radiobutton widget
#
require 'tk'
require 'tk/button'

class TkRadioButton<TkButton
  TkCommandNames = ['radiobutton'.freeze].freeze
  WidgetClassName = 'Radiobutton'.freeze
  WidgetClassNames[WidgetClassName] = self
  #def create_self(keys)
  #  if keys and keys != None
  #    tk_call_without_enc('radiobutton', @path, *hash_kv(keys, true))
  #  else
  #    tk_call_without_enc('radiobutton', @path)
  #  end
  #end
  #private :create_self

  def deselect
    tk_send_without_enc('deselect')
    self
  end
  def select
    tk_send_without_enc('select')
    self
  end
  def variable(v)
    configure 'variable', tk_trace_variable(v)
  end

  def get_value
    var = tk_send_without_enc('cget', '-variable')
    if TkVariable::USE_TCLs_SET_VARIABLE_FUNCTIONS
      _fromUTF8(INTERP._get_global_var(var))
    else
      INTERP._eval(Kernel.format('global %s; set %s', var, var))
    end
  end

  def set_value(val)
    var = tk_send_without_enc('cget', '-variable')
    if TkVariable::USE_TCLs_SET_VARIABLE_FUNCTIONS
      _fromUTF8(INTERP._set_global_var(var, _get_eval_string(val, true)))
    else
      s = '"' + _get_eval_string(val).gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
      INTERP._eval(Kernel.format('global %s; set %s %s', var, var, s))
    end
  end
end
TkRadiobutton = TkRadioButton
