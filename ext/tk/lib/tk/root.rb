#
# tk/root.rb : treat root widget
#
require 'tk'
require 'tk/wm'

class TkRoot<TkWindow
  include Wm

=begin
  ROOT = []
  def TkRoot.new(keys=nil)
    if ROOT[0]
      Tk_WINDOWS["."] = ROOT[0]
      return ROOT[0]
    end
    new = super(:without_creating=>true, :widgetname=>'.')
    if keys  # wm commands
      keys.each{|k,v|
	if v.kind_of? Array
	  new.send(k,*v)
	else
	  new.send(k,v)
	end
      }
    end
    ROOT[0] = new
    Tk_WINDOWS["."] = new
  end
=end
  def TkRoot.new(keys=nil, &b)
    unless TkCore::INTERP.tk_windows['.']
      TkCore::INTERP.tk_windows['.'] = 
	super(:without_creating=>true, :widgetname=>'.'){}
    end
    root = TkCore::INTERP.tk_windows['.']
    if keys  # wm commands
      keys.each{|k,v|
	if v.kind_of? Array
	  root.send(k,*v)
	else
	  root.send(k,v)
	end
      }
    end
    root.instance_eval(&b) if block_given?
    root
  end

  WidgetClassName = 'Tk'.freeze
  WidgetClassNames[WidgetClassName] = self

  def create_self
    @path = '.'
  end
  private :create_self

  def path
    "."
  end

  def TkRoot.destroy
    TkCore::INTERP._invoke('destroy', '.')
  end
end
