#
#   use-loader.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

require "irb/cmd/load"
require "irb/ext/loader"

class Object
  alias __original__load__IRB_use_loader__ load
  alias __original__require__IRB_use_loader__ require
end

module IRB
  module ExtendCommandBundle
    # Loads the given file similarly to Kernel#load, see IrbLoader#irb_load
    def irb_load(*opts, &b)
      ExtendCommand::Load.execute(irb_context, *opts, &b)
    end
    # Loads the given file similarly to Kernel#require
    def irb_require(*opts, &b)
      ExtendCommand::Require.execute(irb_context, *opts, &b)
    end
  end

  class Context

    IRB.conf[:USE_LOADER] = false

    # Returns whether +irb+'s own file reader method is used by
    # +load+/+require+ or not.
    #
    # This mode is globally affected (irb-wide).
    def use_loader
      IRB.conf[:USE_LOADER]
    end

    alias use_loader? use_loader

    # Sets IRB.conf[:USE_LOADER]
    #
    # See #use_loader for more information.
    def use_loader=(opt)

      if IRB.conf[:USE_LOADER] != opt
	IRB.conf[:USE_LOADER] = opt
	if opt
	  if !$".include?("irb/cmd/load")
	  end
	  (class<<@workspace.main;self;end).instance_eval {
	    alias_method :load, :irb_load
	    alias_method :require, :irb_require
	  }
	else
	  (class<<@workspace.main;self;end).instance_eval {
	    alias_method :load, :__original__load__IRB_use_loader__
	    alias_method :require, :__original__require__IRB_use_loader__
	  }
	end
      end
      print "Switch to load/require#{unless use_loader; ' non';end} trace mode.\n" if verbose?
      opt
    end
  end
end


