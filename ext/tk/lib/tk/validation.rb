#
#  tk/validation.rb - validation support module for entry, spinbox, and so on
#
require 'tk'

module Tk
  module ValidateConfigure
    def __validation_class_list
      # maybe need to override
      []
    end

    def __get_validate_key2class
      k2c = {}
      __validation_class_list.each{|klass|
	klass._config_keys.each{|key|
	  k2c[key.to_s] = klass
	}
      }
      k2c
    end

    def configure(slot, value=TkComm::None)
      key2class = __get_validate_key2class

      if slot.kind_of?(Hash)
	slot = _symbolkey2str(slot)
	key2class.each{|key, klass|
	  if slot[key].kind_of?(Array)
	    cmd, *args = slot[key]
	    slot[key] = klass.new(cmd, args.join(' '))
	  elsif slot[key].kind_of? Proc
	    slot[key] = klass.new(slot[key])
	  end
	}
	super(slot)

      else
	slot = slot.to_s
	if (klass = key2class[slot])
	  if value.kind_of? Array
	    cmd, *args = value
	    value = klass.new(cmd, args.join(' '))
	  elsif value.kind_of? Proc
	    value = klass.new(value)
	  end
	end
	super(slot, value)
      end

      self
    end
  end

  module ItemValidateConfigure
    def __item_validation_class_list(id)
      # maybe need to override
      []
    end

    def __get_item_validate_key2class(id)
      k2c = {}
      __item_validation_class_list(id).each{|klass|
	klass._config_keys.each{|key|
	  k2c[key.to_s] = klass
	}
      }
    end

    def itemconfigure(tagOrId, slot, value=TkComm::None)
      key2class = __get_item_validate_key2class(tagid(tagOrId))

      if slot.kind_of?(Hash)
	slot = _symbolkey2str(slot)
	key2class.each{|key, klass|
	  if slot[key].kind_of?(Array)
	    cmd, *args = slot[key]
	    slot[key] = klass.new(cmd, args.join(' '))
	  elsif slot[key].kind_of? Proc
	    slot[key] = klass.new(slot[key])
	  end
	}
	super(slot)

      else
	slot = slot.to_s
	if (klass = key2class[slot])
	  if value.kind_of? Array
	    cmd, *args = value
	    value = klass.new(cmd, args.join(' '))
	  elsif value.kind_of? Proc
	    value = klass.new(value)
	  end
	end
	super(slot, value)
      end

      self
    end
  end
end

module TkValidation
  include Tk::ValidateConfigure

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
      KEY_TBL = [
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

      PROC_TBL = [
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

      _setup_subst_table(KEY_TBL, PROC_TBL);

      def self.ret_val(val)
	(val)? '1': '0'
      end

      #def self._get_extra_args_tbl
      #  # return an array of convert procs
      #  []
      #end
    end

    ##############################

    def self._config_keys
      # array of config-option key (string or symbol)
      ['vcmd', 'validatecommand', 'invcmd', 'invalidcommand']
    end

    def _initialize_for_cb_class(klass, cmd = Proc.new, *args)
      extra_args_tbl = klass._get_extra_args_tbl

      if args.compact.size > 0
	args = args.join(' ')
	keys = klass._get_subst_key(args)
	if cmd.kind_of?(String)
	  id = cmd
	elsif cmd.kind_of?(TkCallbackEntry)
	  @id = install_cmd(cmd)
	else
	  @id = install_cmd(proc{|*arg|
	     ex_args = []
	     extra_args_tbl.reverse_each{|conv| ex_args << conv.call(args.pop)}
	     klass.ret_val(cmd.call(
               *(ex_args.concat(klass.scan_args(keys, arg)))
             ))
	  }) + ' ' + args
	end
      else
	keys, args = klass._get_all_subst_keys
	if cmd.kind_of?(String)
	  id = cmd
	elsif cmd.kind_of?(TkCallbackEntry)
	  @id = install_cmd(cmd)
	else
	  @id = install_cmd(proc{|*arg|
	     ex_args = []
	     extra_args_tbl.reverse_each{|conv| ex_args << conv.call(args.pop)}
	     klass.ret_val(cmd.call(
               *(ex_args << klass.new(*klass.scan_args(keys,arg)))
	     ))
	  }) + ' ' + args
	end
      end
    end

    def initialize(cmd = Proc.new, *args)
      _initialize_for_cb_class(ValidateArgs, cmd, *args)
    end

    def to_eval
      @id
    end
  end

  #####################################

  def __validation_class_list
    super << ValidateCmd
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
