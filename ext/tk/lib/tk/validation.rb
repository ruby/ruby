#
#  tk/validation.rb - validation support module for entry, spinbox, and so on
#
require 'tk'

module TkValidation
  class ValidateCmd
    include TkComm

    module Action
      Insert = 1
      Delete = 0
      Others = -1
      Focus  = -1
      Forced = -1
      Textvariable = -1
      TextVariable = -1
    end

    class ValidateArgs < TkUtil::CallbackSubst
      key_tbl = [
	[ ?d, ?n, :action ], 
	[ ?i, ?x, :index ], 
	[ ?s, ?e, :current ], 
	[ ?v, ?s, :type ], 
	[ ?P, ?e, :value ], 
	[ ?S, ?e, :string ], 
	[ ?V, ?s, :triggered ], 
	[ ?W, ?w, :widget ], 
	nil
      ]

      proc_tbl = [
	[ ?n, TkComm.method(:number) ], 
	[ ?s, TkComm.method(:string) ], 
	[ ?w, TkComm.method(:window) ], 

	[ ?e, proc{|val|
	    enc = Tk.encoding
	    if enc
	      Tk.fromUTF8(TkComm::string(val), enc)
	    else
	      TkComm::string(val)
	    end
	  }
	], 

	[ ?x, proc{|val|
	    idx = TkComm::number(val)
	    if idx < 0
	      nil
	    else
	      idx
	    end
	  }
	], 

	nil
      ]

      _setup_subst_table(key_tbl, proc_tbl);
    end

    def initialize(cmd = Proc.new, *args)
      if args.compact.size > 0
	args = args.join(' ')
	keys = ValidateArgs._get_subst_key(args)
	if cmd.kind_of?(String)
	  id = cmd
	elsif cmd.kind_of?(TkCallbackEntry)
	  @id = install_cmd(cmd)
	else
	  @id = install_cmd(proc{|*arg|
	     (cmd.call(*ValidateArgs.scan_args(keys, arg)))? '1':'0'
	  }) + ' ' + args
	end
      else
	keys, args = ValidateArgs._get_all_subst_keys
	if cmd.kind_of?(String)
	  id = cmd
	elsif cmd.kind_of?(TkCallbackEntry)
	  @id = install_cmd(cmd)
	else
	  @id = install_cmd(proc{|*arg|
	     (cmd.call(
                ValidateArgs.new(*ValidateArgs.scan_args(keys,arg)))
             )? '1': '0'
	  }) + ' ' + args
	end
      end
    end

    def to_eval
      @id
    end
  end

  #####################################

  def configure(slot, value=TkComm::None)
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

  def validatecommand(cmd = Proc.new, args = nil)
    if cmd.kind_of?(ValidateCmd)
      configure('validatecommand', cmd)
    elsif args
      configure('validatecommand', [cmd, args])
    else
      configure('validatecommand', cmd)
    end
  end
  alias vcmd validatecommand

  def invalidcommand(cmd = Proc.new, args = nil)
    if cmd.kind_of?(ValidateCmd)
      configure('invalidcommand', cmd)
    elsif args
      configure('invalidcommand', [cmd, args])
    else
      configure('invalidcommand', cmd)
    end
  end
  alias invcmd invalidcommand
end
