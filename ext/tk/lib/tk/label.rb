#
# tk/label.rb : treat label widget
#
require 'tk'

class TkLabel<TkWindow
  TkCommandNames = ['label'.freeze].freeze
  WidgetClassName = 'Label'.freeze
  WidgetClassNames[WidgetClassName] = self
  #def create_self(keys)
  #  if keys and keys != None
  #    tk_call_without_enc('label', @path, *hash_kv(keys, true))
  #  else
  #    tk_call_without_enc('label', @path)
  #  end
  #end
  #private :create_self
end
