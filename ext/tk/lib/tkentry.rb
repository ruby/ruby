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

  def bbox(index)
    tk_send 'bbox', index
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

  def validate(mode = nil)
    if mode
      configure 'validate', mode
    else
      if tk_send('validate') == '0'
	false
      else 
	true
      end
    end
  end

  class ValidateCmd
    include TkComm

    class ValidateArgs
      def initialize(d,i,s,v,pp,ss,vv,ww)
	@action = d
	@index = i
	@current = s
	@type = v
	@value = pp
	@string = ss
	@triggered = vv
	@widget = ww
      end
      attr :action
      attr :index
      attr :current
      attr :type
      attr :value
      attr :string
      attr :triggered
      attr :widget
    end

    def initialize(cmd = Proc.new, args=nil)
      if args
	@id = install_cmd(proc{|*arg|
			    TkUtil.eval_cmd cmd, *arg
			  }) + " " + args
      else
	@id = install_cmd(proc{|arg|
			    TkUtil.eval_cmd cmd, ValidateArgs.new(*arg)
			  }) + ' %d %i %s %v %P %S %V %W'
      end
    end

    def to_eval
      @id
    end
  end

  def validatecommand(cmd = ValidateCmd.new, args = nil)
    if cmd.kind_of?(ValidateCmd)
      configure('validatecommand', cmd)
    else
      configure('validatecommand', ValidateCmd.new(cmd, args))
    end
  end
  alias vcmd validatecommand

  def invalidcommand(cmd = ValidateCmd.new, args = nil)
    if cmd.kind_of?(ValidateCmd)
      configure('invalidcommand', cmd)
    else
      configure('invalidcommand', ValidateCmd.new(cmd, args))
    end
  end
  alias invcmd invalidcommand

  def value
    tk_send 'get'
  end
  def value= (val)
    tk_send 'delete', 0, 'end'
    tk_send 'insert', 0, val
  end
end

class TkSpinbox<TkEntry
  WidgetClassName = 'Spinbox'.freeze
  WidgetClassNames[WidgetClassName] = self
  def self.to_eval
    WidgetClassName
  end

  def create_self
    tk_call 'spinbox', @path
  end

  def identify(x, y)
    tk_send 'identify', x, y
  end

  def spinup
    tk_send 'invoke', 'spinup'
  end

  def spindown
    tk_send 'invoke', 'spindown'
  end

  def set(str)
    tk_send 'set', str
  end
end
