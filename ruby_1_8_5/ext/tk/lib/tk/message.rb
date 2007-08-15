#
# tk/message.rb : treat message widget
#
require 'tk'
require 'tk/label'

class TkMessage<TkLabel
  TkCommandNames = ['message'.freeze].freeze
  WidgetClassName = 'Message'.freeze
  WidgetClassNames[WidgetClassName] = self
  #def create_self(keys)
  #  if keys and keys != None
  #    tk_call_without_enc('message', @path, *hash_kv(keys, true))
  #  else
  #    tk_call_without_enc('message', @path)
  #  end
  #end
  private :create_self
end
