#
# tk/root.rb : treat root widget
#
require 'tk'
require 'tk/wm'
require 'tk/menuspec'

class TkRoot<TkWindow
  include Wm
  include TkMenuSpec

  def __methodcall_optkeys  # { key=>method, ... }
    TOPLEVEL_METHODCALL_OPTKEYS
  end
  private :__methodcall_optkeys

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

    keys = _symbolkey2str(keys)

    # wm commands
    root.instance_eval{
      __methodcall_optkeys.each{|key, method|
        value = keys.delete(key.to_s)
        self.__send__(method, value) if value
      }
    }

    if keys  # wm commands ( for backward comaptibility )
      keys.each{|k,v|
        if v.kind_of? Array
          root.__send__(k,*v)
        else
          root.__send__(k,v)
        end
      }
    end

    root.instance_eval(&b) if block_given?
    root
  end

  WidgetClassName = 'Tk'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.to_eval
    # self::WidgetClassName
    '.'
  end

  def create_self
    @path = '.'
  end
  private :create_self

  def path
    "."
  end

  def add_menu(menu_info, tearoff=false, opts=nil)
    # See tk/menuspec.rb for menu_info.
    # opts is a hash of default configs for all of cascade menus. 
    # Configs of menu_info can override it. 
    if tearoff.kind_of?(Hash)
      opts = tearoff
      tearoff = false
    end
    _create_menubutton(self, menu_info, tearoff, opts)
  end

  def add_menubar(menu_spec, tearoff=false, opts=nil)
    # See tk/menuspec.rb for menu_spec.
    # opts is a hash of default configs for all of cascade menus.
    # Configs of menu_spec can override it. 
    menu_spec.each{|info| add_menu(info, tearoff, opts)}
    self.menu
  end

  def TkRoot.destroy
    TkCore::INTERP._invoke('destroy', '.')
  end
end
