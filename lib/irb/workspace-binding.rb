#
#   workspace-binding.rb - 
#   	$Release Version: $
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(Nihon Rational Software Co.,Ltd)
#
# --
#
#   
#


module IRB
  # create new workspace. 
  def IRB.workspace_binding(*main)
    if @CONF[:SINGLE_IRB]
      bind = TOPLEVEL_BINDING
    else
      case @CONF[:CONTEXT_MODE]
      when 0
	bind = eval("proc{binding}.call",
		    TOPLEVEL_BINDING, 
		    "(irb_local_binding)",
		    1)
      when 1
	require "tempfile"
	f = Tempfile.open("irb-binding")
	f.print <<EOF
	$binding = binding
EOF
	f.close
	load f.path
	bind = $binding

      when 2
	unless defined? BINDING_QUEUE
	  require "thread"
	  
	  IRB.const_set("BINDING_QUEUE", SizedQueue.new(1))
	  Thread.abort_on_exception = true
	  Thread.start do
	    eval "require \"irb/workspace-binding-2\"", TOPLEVEL_BINDING, __FILE__, __LINE__
	  end
	  Thread.pass

	end

	bind = BINDING_QUEUE.pop

      when 3
	bind = eval("def irb_binding; binding; end; irb_binding",
		    TOPLEVEL_BINDING, 
		    __FILE__,
		    __LINE__ - 3)
      end
    end
    unless main.empty?
      @CONF[:__MAIN__] = main[0]
      case main[0]
      when Module
	bind = eval("IRB.conf[:__MAIN__].module_eval('binding')", bind)
      else
	begin 
	  bind = eval("IRB.conf[:__MAIN__].instance_eval('binding')", bind)
	rescue TypeError
	  IRB.fail CanNotChangeBinding, main[0].inspect
	end
      end
    end
    eval("_=nil", bind)
    bind
  end

  def IRB.delete_caller
  end
end
