#
#   tk/virtevent.rb : treats virtual events
#                     1998/07/16 by Hidetoshi Nagai <nagai@ai.kyutech.ac.jp>
#
require 'tk'

class TkVirtualEvent<TkObject
  extend Tk

  TkCommandNames = ['event'.freeze].freeze

  TkVirtualEventID = ["VirtEvent".freeze, "00000".taint].freeze
  TkVirtualEventTBL = TkCore::INTERP.create_table

  TkCore::INTERP.init_ip_env{ TkVirtualEventTBL.clear }

  class PreDefVirtEvent<self
    def initialize(event, *sequences)
      @path = @id = event
      TkVirtualEvent::TkVirtualEventTBL[@id] = self
      add(*sequences)
    end
  end

  def TkVirtualEvent.getobj(event)
    obj = TkVirtualEventTBL[event]
    if obj
      obj
    else
      if tk_call_without_enc('event', 'info').index("<#{event}>")
        PreDefVirtEvent.new(event)
      else
        fail ArgumentError, "undefined virtual event '<#{event}>'"
      end
    end
  end

  def TkVirtualEvent.info
    tk_call_without_enc('event', 'info').split(/\s+/).collect!{|seq|
      TkVirtualEvent.getobj(seq[1..-2])
    }
  end

  def initialize(*sequences)
    # @path = @id = '<' + TkVirtualEventID.join('') + '>'
    @path = @id = '<' + TkVirtualEventID.join(TkCore::INTERP._ip_id_) + '>'
    TkVirtualEventID[1].succ!
    add(*sequences)
  end

  def add(*sequences)
    if sequences != []
      tk_call_without_enc('event', 'add', "<#{@id}>", 
                          *(sequences.collect{|seq| 
                              "<#{tk_event_sequence(seq)}>"
                            }) )
      TkVirtualEventTBL[@id] = self
    end
    self
  end

  def delete(*sequences)
    if sequences == []
      tk_call_without_enc('event', 'delete', "<#{@id}>")
      TkVirtualEventTBL.delete(@id)
    else
      tk_call_without_enc('event', 'delete', "<#{@id}>", 
                          *(sequences.collect{|seq| 
                              "<#{tk_event_sequence(seq)}>"
                            }) )
      TkVirtualEventTBL.delete(@id) if info == []
    end
    self
  end

  def info
    tk_call_without_enc('event','info',"<#{@id}>").split(/\s+/).collect!{|seq|
      l = seq.scan(/<*[^<>]+>*/).collect!{|subseq|
        case (subseq)
        when /^<<[^<>]+>>$/
          TkVirtualEvent.getobj(subseq[1..-2])
        when /^<[^<>]+>$/
          subseq[1..-2]
        else
          subseq.split('')
        end
      }.flatten
      (l.size == 1) ? l[0] : l
    }
  end
end
