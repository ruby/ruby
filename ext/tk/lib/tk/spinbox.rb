#
#		tk/spinbox.rb - Tk spinbox classes
#			$Date$
#			by Yukihiro Matsumoto <matz@caelum.co.jp>
#
require 'tk'
require 'tk/entry'

class TkSpinbox<TkEntry
  TkCommandNames = ['spinbox'.freeze].freeze
  WidgetClassName = 'Spinbox'.freeze
  WidgetClassNames[WidgetClassName] = self

  #def create_self(keys)
  #  tk_call_without_enc('spinbox', @path)
  #  if keys and keys != None
  #    configure(keys)
  #  end
  #end
  #private :create_self

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
