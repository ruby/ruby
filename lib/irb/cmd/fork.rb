#
#   fork.rb - 
#   	$Release Version: 0.9.5 $
#   	$Revision: 1.2.2.1 $
#   	$Date: 2005/04/19 19:24:58 $
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#   
#

@RCS_ID='-$Id: fork.rb,v 1.2.2.1 2005/04/19 19:24:58 keiju Exp $-'


module IRB
  module ExtendCommand
    class Fork<Nop
      def execute(&block)
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
    end
  end
end


