#
# tk/composite.rb : 
#
require 'tk'

module TkComposite
  include Tk
  extend Tk

  def initialize(parent=nil, *args)
    @delegates = {} 

    if parent.kind_of? Hash
      keys = _symbolkey2str(parent)
      parent = keys.delete('parent')
      @frame = TkFrame.new(parent)
      @delegates['DEFAULT'] = @frame
      @path = @epath = @frame.path
      initialize_composite(keys)
    else
      @frame = TkFrame.new(parent)
      @delegates['DEFAULT'] = @frame
      @path = @epath = @frame.path
      initialize_composite(*args)
    end
  end

  def epath
    @epath
  end

  def initialize_composite(*args) end
  private :initialize_composite

  def delegate(option, *wins)
    if @delegates[option].kind_of?(Array)
      for i in wins
	@delegates[option].push(i)
      end
    else
      @delegates[option] = wins
    end
  end

  def configure(slot, value=None)
    if slot.kind_of? Hash
      slot.each{|slot,value| configure slot, value}
    else
      if @delegates and @delegates[slot]
	for i in @delegates[slot]
	  if not i
	    i = @delegates['DEFALUT']
	    redo
	  else
	    last = i.configure(slot, value)
	  end
	end
	last
      else
	super
      end
    end
  end
end
