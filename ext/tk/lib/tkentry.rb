#
#		tkentry.rb - Tk entry classes
#			$Date$
#			by Yukihiro Matsumoto <matz@caelum.co.jp>

require 'tk.rb'

class TkEntry<TkLabel
  include Scrollable

  TkCommandNames = ['entry'.freeze].freeze
  WidgetClassName = 'Entry'.freeze
  WidgetClassNames[WidgetClassName] = self

  class ValidateCmd
    include TkComm

    class ValidateArgs
      VARG_KEY  = 'disvPSVW'
      VARG_TYPE = 'nnsssssw'

      def self.scan_args(arg_str, arg_val)
	arg_cnv = []
	arg_str.strip.split(/\s+/).each_with_index{|kwd,idx|
	  if kwd =~ /^%(.)$/
	    if num = VARG_KEY.index($1)
	      case VARG_TYPE[num]
	      when ?n
		arg_cnv << TkComm::number(arg_val[idx])
	      when ?s
		arg_cnv << TkComm::string(arg_val[idx])
	      when ?w
		arg_cnv << TkComm::window(arg_val[idx])
	      else
		arg_cnv << arg_val[idx]
	      end
	    else
	      arg_cnv << arg_val[idx]
	    end
	  else
	    arg_cnv << arg_val[idx]
	  end
	}
	arg_cnv
      end

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
	@id = 
	  install_cmd(proc{|*arg|
			TkUtil.eval_cmd(cmd, ValidateArgs.scan_args(args, arg))
		      }) + " " + args
      else
	args = ' %d %i %s %v %P %S %V %W'
	@id = 
	  install_cmd(proc{|*arg|
	    TkUtil.eval_cmd(
		cmd, 
		ValidateArgs.new(ValidateArgs.scan_args(args, arg))
	    )
	  }) + args
      end
    end

    def to_eval
      @id
    end
  end

  def create_self(keys)
    if keys and keys != None
      tk_call 'entry', @path, *hash_kv(keys)
    else
      tk_call 'entry', @path
    end
  end

  def configure(slot, value=None)
    if slot.kind_of? Hash
      slot = _symbolkey2str(slot)
      if slot['vcmd'].kind_of? Array
	cmd, *args = slot['vcmd']
	slot['vcmd'] = ValidateCmd.new(cmd, args.join(' '))
      elsif slot['vcmd'].kind_of? Proc
	slot['vcmd'] = ValidateCmd.new(slot['vcmd'])
      end
      if slot['validatecommand'].kind_of? Array
	cmd, *args = slot['validatecommand']
	slot['validatecommand'] = ValidateCmd.new(cmd, args.join(' '))
      elsif slot['validatecommand'].kind_of? Proc
	slot['validatecommand'] = ValidateCmd.new(slot['validatecommand'])
      end
      if slot['invcmd'].kind_of? Array
	cmd, *args = slot['invcmd']
	slot['invcmd'] = ValidateCmd.new(cmd, args.join(' '))
      elsif slot['invcmd'].kind_of? Proc
	slot['invcmd'] = ValidateCmd.new(slot['invcmd'])
      end
      if slot['invalidcommand'].kind_of? Array
	cmd, *args = slot['invalidcommand']
	slot['invalidcommand'] = ValidateCmd.new(cmd, args.join(' '))
      elsif slot['invalidcommand'].kind_of? Proc
	slot['invalidcommand'] = ValidateCmd.new(slot['invalidcommand'])
      end
      super(slot)
    else
      if (slot == 'vcmd' || slot == :vcmd || 
          slot == 'validatecommand' || slot == :validatecommand || 
	  slot == 'invcmd' || slot == :invcmd || 
          slot == 'invalidcommand' || slot == :invalidcommand)
	if value.kind_of? Array
	  cmd, *args = value
	  value = ValidateCmd.new(cmd, args.join(' '))
	elsif value.kind_of? Proc
	  value = ValidateCmd.new(value)
	end
      end
      super(slot, value)
    end
    self
  end

  def bbox(index)
    list(tk_send('bbox', index))
  end
  def cursor
    number(tk_send('index', 'insert'))
  end
  def cursor=(index)
    tk_send 'icursor', index
    self
  end
  def index(index)
    number(tk_send('index', index))
  end
  def insert(pos,text)
    tk_send 'insert', pos, text
    self
  end
  def delete(first, last=None)
    tk_send 'delete', first, last
    self
  end
  def mark(pos)
    tk_send 'scan', 'mark', pos
    self
  end
  def dragto(pos)
    tk_send 'scan', 'dragto', pos
    self
  end
  def selection_adjust(index)
    tk_send 'selection', 'adjust', index
    self
  end
  def selection_clear
    tk_send 'selection', 'clear'
    self
  end
  def selection_from(index)
    tk_send 'selection', 'from', index
    self
  end
  def selection_present()
    bool(tk_send('selection', 'present'))
  end
  def selection_range(s, e)
    tk_send 'selection', 'range', s, e
    self
  end
  def selection_to(index)
    tk_send 'selection', 'to', index
    self
  end

  def validate(mode = nil)
    if mode
      configure 'validate', mode
    else
      bool(tk_send('validate'))
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
  TkCommandNames = ['spinbox'.freeze].freeze
  WidgetClassName = 'Spinbox'.freeze
  WidgetClassNames[WidgetClassName] = self

  def create_self(keys)
    if keys and keys != None
      tk_call 'spinbox', @path, *hash_kv(keys)
    else
      tk_call 'spinbox', @path
    end
  end

  def identify(x, y)
    tk_send 'identify', x, y
  end

  def spinup
    tk_send 'invoke', 'spinup'
    self
  end

  def spindown
    tk_send 'invoke', 'spindown'
    self
  end

  def set(str)
    tk_send 'set', str
  end
end
