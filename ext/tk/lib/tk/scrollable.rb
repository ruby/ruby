#
# tk/scrollable.rb : module for scrollable widget
#
require 'tk'

module Tk
  module Scrollable
    def xscrollcommand(cmd=Proc.new)
      configure_cmd 'xscrollcommand', cmd
    end
    def yscrollcommand(cmd=Proc.new)
      configure_cmd 'yscrollcommand', cmd
    end
    def xview(*index)
      if index.size == 0
	list(tk_send_without_enc('xview'))
      else
	tk_send_without_enc('xview', *index)
	self
      end
    end
    def yview(*index)
      if index.size == 0
	list(tk_send_without_enc('yview'))
      else
	tk_send_without_enc('yview', *index)
	self
      end
    end
    def xscrollbar(bar=nil)
      if bar
	@xscrollbar = bar
	@xscrollbar.orient 'horizontal'
	self.xscrollcommand {|*arg| @xscrollbar.set(*arg)}
	@xscrollbar.command {|*arg| self.xview(*arg)}
      end
      @xscrollbar
    end
    def yscrollbar(bar=nil)
      if bar
	@yscrollbar = bar
	@yscrollbar.orient 'vertical'
	self.yscrollcommand {|*arg| @yscrollbar.set(*arg)}
	@yscrollbar.command {|*arg| self.yview(*arg)}
      end
      @yscrollbar
    end
  end
end
