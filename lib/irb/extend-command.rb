#
#   irb/extend-command.rb - irb command extend
#   	$Release Version: 0.7.3$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#
# --
#
#   
#
module IRB
  #
  # IRB extended command
  # (JP: IRB拡張コマンド)
  #
  module ExtendCommand
#    include Loader
    
    def irb_exit(ret = 0)
      irb_context.exit(ret)
    end
    alias irb_quit irb_exit

    def irb_fork(&block)
      pid = send ExtendCommand.irb_original_method_name("fork")
      unless pid 
	class<<self
	  alias_method :exit, ExtendCommand.irb_original_method_name('exit')
	end
	if iterator?
	  begin
	    yield
	  ensure
	    exit
	  end
	end
      end
      pid
    end

    def irb_change_binding(*main)
      irb_context.change_binding(*main)
    end
    alias irb_change_workspace irb_change_binding

    def irb_source(file)
      irb_context.source(file)
    end

    def irb(*obj)
      require "irb/multi-irb"
      IRB.irb(nil, *obj)
    end

    def irb_context
      IRB.conf[:MAIN_CONTEXT]
    end

    def irb_jobs
      require "irb/multi-irb"
      IRB.JobManager
    end

    def irb_fg(key)
      require "irb/multi-irb"
      IRB.JobManager.switch(key)
    end

    def irb_kill(*keys)
      require "irb/multi-irb"
      IRB.JobManager.kill(*keys)
    end

    # extend command functions
    def ExtendCommand.extend_object(obj)
      super
      unless (class<<obj;ancestors;end).include?(ExtendCommand)
	obj.install_aliases
      end
    end

    OVERRIDE_NOTHING = 0
    OVERRIDE_PRIVATE_ONLY = 0x01
    OVERRIDE_ALL = 0x02

    def install_aliases(override = OVERRIDE_NOTHING)

      install_alias_method(:exit, :irb_exit, override | OVERRIDE_PRIVATE_ONLY)
      install_alias_method(:quit, :irb_quit, override | OVERRIDE_PRIVATE_ONLY)
      install_alias_method(:fork, :irb_fork, override | OVERRIDE_PRIVATE_ONLY)
      install_alias_method(:kill, :irb_kill, override | OVERRIDE_PRIVATE_ONLY)

      install_alias_method(:irb_cb, :irb_change_binding, override)
      install_alias_method(:irb_ws, :irb_change_workspace, override)
      install_alias_method(:source, :irb_source, override)
      install_alias_method(:conf, :irb_context, override)
      install_alias_method(:jobs, :irb_jobs, override)
      install_alias_method(:fg, :irb_fg, override)
    end

    # override = {OVERRIDE_NOTHING, OVERRIDE_PRIVATE_ONLY, OVERRIDE_ALL}
    def install_alias_method(to, from, override = OVERRIDE_NOTHING)
      to = to.id2name unless to.kind_of?(String)
      from = from.id2name unless from.kind_of?(String)

      if override == OVERRIDE_ALL or
	  (override == OVERRIDE_PRIVATE_ONLY) && !respond_to?(to) or
	  (override == OVERRIDE_NOTHING) &&  !respond_to?(to, true)
	target = self
	(class<<self;self;end).instance_eval{
	  if target.respond_to?(to, true) && 
	      !target.respond_to?(ExtendCommand.irb_original_method_name(to), true)
	    alias_method(ExtendCommand.irb_original_method_name(to), to) 
	  end
	  alias_method to, from
	}
      else
	print "irb: warn: can't alias #{to} from #{from}.\n"
      end
    end

    def self.irb_original_method_name(method_name)
      "irb_" + method_name + "_org"
    end
  end
end
