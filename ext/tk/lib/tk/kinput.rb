#
# tk/kinput.rb : control kinput
#
require 'tk'

module TkKinput
  include Tk
  extend Tk

  TkCommandNames = [
    'kinput_start'.freeze, 
    'kinput_send_spot'.freeze, 
    'kanjiInput'.freeze
  ].freeze

  def TkKinput.start(window, style=None)
    tk_call('kinput_start', window, style)
  end
  def kinput_start(style=None)
    TkKinput.start(self, style)
  end

  def TkKinput.send_spot(window)
    tk_call('kinput_send_spot', window)
  end
  def kinput_send_spot
    TkKinput.send_spot(self)
  end

  def TkKinput.input_start(window, keys=nil)
    tk_call('kanjiInput', 'start', window, *hash_kv(keys))
  end
  def kanji_input_start(keys=nil)
    TkKinput.input_start(self, keys)
  end

  def TkKinput.attribute_config(window, slot, value=None)
    if slot.kind_of? Hash
      tk_call('kanjiInput', 'attribute', window, *hash_kv(slot))
    else
      tk_call('kanjiInput', 'attribute', window, "-#{slot}", value)
    end
  end
  def kinput_attribute_config(slot, value=None)
    TkKinput.attribute_config(self, slot, value)
  end

  def TkKinput.attribute_info(window, slot=nil)
    if slot
      conf = tk_split_list(tk_call('kanjiInput', 'attribute', 
                                   window, "-#{slot}"))
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_list(tk_call('kanjiInput', 'attribute', window)).collect{|conf|
        conf[0] = conf[0][1..-1]
        conf
      }
    end
  end
  def kinput_attribute_info(slot=nil)
    TkKinput.attribute_info(self, slot)
  end

  def TkKinput.input_end(window)
    tk_call('kanjiInput', 'end', window)
  end
  def kanji_input_end
    TkKinput.input_end(self)
  end
end
