#
#		tkentry.rb - Tk entry classes
#			$Date: 1995/12/07 15:01:10 $
#			by Yukihiro Matsumoto <matz@caelum.co.jp>

require 'tk.rb'

class TkEntry<TkLabel
  def create_self
    tk_call 'entry', @path
  end
  def scrollcommand(cmd)
    configure 'scrollcommand', cmd
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
  def select_adjust(index)
    tk_send 'select', 'adjust', index
  end
  def select_clear
    tk_send 'select', 'clear', 'end'
  end
  def select_from(index)
    tk_send 'select', 'from', index
  end
  def select_present()
    tk_send('select', 'present') == 1
  end
  def select_range(s, e)
    tk_send 'select', 'range', s, e
  end
  def select_to(index)
    tk_send 'select', 'to', index
  end
  def xview(*index)
    tk_send 'xview', *index
  end

  def value
    tk_send 'get'
  end
  def value= (val)
    tk_send 'delete', 0, 'end'
    tk_send 'insert', 0, val
  end
end
