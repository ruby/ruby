#
#		tkentry.rb - Tk entry classes
#			$Date$
#			by Yukihiro Matsumoto <matz@caelum.co.jp>

require 'tk.rb'

class TkEntry<TkLabel
  include Scrollable

  WidgetClassName = 'Entry'.freeze
  WidgetClassNames[WidgetClassName] = self
  def self.to_eval
    WidgetClassName
  end

  def create_self
    tk_call 'entry', @path
  end

  def delete(s, e=None)
    tk_send 'delete', s, e
  end

  def cursor
    tk_send 'index', 'insert'
  end
  def cursor=(index)
    tk_send 'icursor', index
  end
  def index(index)
    number(tk_send('index', index))
  end
  def insert(pos,text)
    tk_send 'insert', pos, text
  end
  def mark(pos)
    tk_send 'scan', 'mark', pos
  end
  def dragto(pos)
    tk_send 'scan', 'dragto', pos
  end
  def selection_adjust(index)
    tk_send 'selection', 'adjust', index
  end
  def selection_clear
    tk_send 'selection', 'clear'
  end
  def selection_from(index)
    tk_send 'selection', 'from', index
  end
  def selection_present()
    tk_send('selection', 'present') == 1
  end
  def selection_range(s, e)
    tk_send 'selection', 'range', s, e
  end
  def selection_to(index)
    tk_send 'selection', 'to', index
  end

  def value
    tk_send 'get'
  end
  def value= (val)
    tk_send 'delete', 0, 'end'
    tk_send 'insert', 0, val
  end
end
