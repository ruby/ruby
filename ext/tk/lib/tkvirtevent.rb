#
#   tkvirtevent.rb : treats virtual events
#                     1998/07/16 by Hidetoshi Nagai <nagai@ai.kyutech.ac.jp>
#
require 'tk'

class TkVirtualEvent<TkObject
  extend Tk

  TkVirturlEventID = [0]
  TkVirturlEventTBL = {}

  def TkVirtualEvent.getobj(event)
    obj = TkVirturlEventTBL[event]
    obj ? obj : event
  end

  def TkVirtualEvent.info
    tk_call('event', 'info').split(/\s+/).filter{|seq|
      TkVirtualEvent.getobj(seq[1..-2])
    }
  end

  def initialize(*sequences)
    @path = @id = format("<VirtEvent%.4d>", TkVirturlEventID[0])
    TkVirturlEventID[0] += 1
    add(*sequences)
  end

  def add(*sequences)
    if sequences != []
      tk_call('event', 'add', "<#{@id}>", 
	      *(sequences.collect{|seq| "<#{tk_event_sequence(seq)}>"}) )
      TkVirturlEventTBL[@id] = self
    end
    self
  end

  def delete(*sequences)
    if sequences == []
      tk_call('event', 'delete', "<#{@id}>")
      TkVirturlEventTBL[@id] = nil
    else
      tk_call('event', 'delete', "<#{@id}>", 
	      *(sequences.collect{|seq| "<#{tk_event_sequence(seq)}>"}) )
      TkVirturlEventTBL[@id] = nil if info == []
    end
    self
  end

  def info
    tk_call('event', 'info', "<#{@id}>").split(/\s+/).filter{|seq|
      l = seq.scan(/<*[^<>]+>*/).filter{|subseq|
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
