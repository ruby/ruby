#
# tk/radiobutton.rb : treat radiobutton widget
#
require 'tk'
require 'tk/button'

class TkRadioButton<TkButton
  TkCommandNames = ['radiobutton'.freeze].freeze
  WidgetClassName = 'Radiobutton'.freeze
  WidgetClassNames[WidgetClassName] = self
  def create_self(keys)
    if keys and keys != None
      tk_call_without_enc('radiobutton', @path, *hash_kv(keys, true))
    else
      tk_call_without_enc('radiobutton', @path)
    end
  end
  private :create_self

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
end
TkRadiobutton = TkRadioButton
