#
# tk/labelframe.rb : treat labelframe widget
#
require 'tk'
require 'tk/frame'

class TkLabelFrame<TkFrame
  TkCommandNames = ['labelframe'.freeze].freeze
  WidgetClassName = 'Labelframe'.freeze
  WidgetClassNames[WidgetClassName] = self
  #def create_self(keys)
  #  if keys and keys != None
  #    tk_call_without_enc('labelframe', @path, *hash_kv(keys, true))
  #  else
  #    tk_call_without_enc('labelframe', @path)
  #  end
  #end
  #private :create_self

  def __val2ruby_optkeys  # { key=>proc, ... }
    super().update('labelwidget'=>proc{|v| window(v)})
  end
  private :__val2ruby_optkeys
end
TkLabelframe = TkLabelFrame
