#
# tk/checkbutton.rb : treat checkbutton widget
#
require 'tk'
require 'tk/radiobutton'

class TkCheckButton<TkRadioButton
  TkCommandNames = ['checkbutton'.freeze].freeze
  WidgetClassName = 'Checkbutton'.freeze
  WidgetClassNames[WidgetClassName] = self
  #def create_self(keys)
  #  if keys and keys != None
  #    tk_call_without_enc('checkbutton', @path, *hash_kv(keys, true))
  #  else
  #    tk_call_without_enc('checkbutton', @path)
  #  end
  #end
  #private :create_self

  def toggle
    tk_send_without_enc('toggle')
    self
  end
end
TkCheckbutton = TkCheckButton
