#
# tk/wm.rb : methods for wm command
#
require 'tk'

module Tk
  module Wm
    include TkComm

    TkCommandNames = ['wm'.freeze].freeze

    def aspect(*args)
      if args.length == 0
        list(tk_call_without_enc('wm', 'aspect', path))
      else
        tk_call('wm', 'aspect', path, *args)
        self
      end
    end

    def attributes(slot=nil,value=None)
      if slot == nil
        lst = tk_split_list(tk_call('wm', 'attributes', path))
        info = {}
        while key = lst.shift
          info[key[1..-1]] = lst.shift
        end
        info
      elsif slot.kind_of? Hash
        tk_call('wm', 'attributes', path, *hash_kv(slot))
        self
      elsif value == None
        tk_call('wm', 'attributes', path, "-#{slot}")
      else
        tk_call('wm', 'attributes', path, "-#{slot}", value)
        self
      end
    end

    def client(name=None)
      if name == None
        tk_call('wm', 'client', path)
      else
        name = '' if name == nil
        tk_call('wm', 'client', path, name)
        self
      end
    end

    def colormapwindows(*args)
      if args.size == 0
        list(tk_call_without_enc('wm', 'colormapwindows', path))
      else
        tk_call_without_enc('wm', 'colormapwindows', path, *args)
        self
      end
    end

    def wm_command(value=nil)
      if value
        tk_call('wm', 'command', path, value)
        self
      else
        #procedure(tk_call('wm', 'command', path))
        tk_call('wm', 'command', path)
      end
    end

    def deiconify(ex = true)
      tk_call_without_enc('wm', 'deiconify', path) if ex
      self
    end

    def focusmodel(mode = nil)
      if mode
        tk_call_without_enc('wm', 'focusmodel', path, mode)
        self
      else
        tk_call_without_enc('wm', 'focusmodel', path)
      end
    end

    def frame
      tk_call_without_enc('wm', 'frame', path)
    end

    def geometry(geom=nil)
      if geom
        tk_call_without_enc('wm', 'geometry', path, geom)
        self
      else
        tk_call_without_enc('wm', 'geometry', path)
      end
    end

    def wm_grid(*args)
      if args.size == 0
        list(tk_call_without_enc('wm', 'grid', path))
      else
        tk_call_without_enc('wm', 'grid', path, *args)
        self
      end
    end

    def group(leader = nil)
      if leader
        tk_call('wm', 'group', path, leader)
        self
      else
        window(tk_call('wm', 'group', path))
      end
    end

    def iconbitmap(bmp=nil)
      if bmp
        tk_call_without_enc('wm', 'iconbitmap', path, bmp)
        self
      else
        image_obj(tk_call_without_enc('wm', 'iconbitmap', path))
      end
    end

    def iconphoto(*imgs)
      # Windows only
      tk_call_without_enc('wm', 'iconphoto', path, *imgs)
      self
    end

    def iconphoto_default(*imgs)
      # Windows only
      tk_call_without_enc('wm', 'iconphoto', path, '-default', *imgs)
      self
    end

    def iconify(ex = true)
      tk_call_without_enc('wm', 'iconify', path) if ex
      self
    end

    def iconmask(bmp=nil)
      if bmp
        tk_call_without_enc('wm', 'iconmask', path, bmp)
        self
      else
        image_obj(tk_call_without_enc('wm', 'iconmask', path))
      end
    end

    def iconname(name=nil)
      if name
        tk_call('wm', 'iconname', path, name)
        self
      else
        tk_call('wm', 'iconname', path)
      end
    end

    def iconposition(*args)
      if args.size == 0
        list(tk_call_without_enc('wm', 'iconposition', path))
      else
        tk_call_without_enc('wm', 'iconposition', path, *args)
        self
      end
    end

    def iconwindow(win = nil)
      if win
        tk_call_without_enc('wm', 'iconwindow', path, win)
        self
      else
        w = tk_call_without_enc('wm', 'iconwindow', path)
        (w == '')? nil: window(w)
      end
    end

    def maxsize(*args)
      if args.size == 0
        list(tk_call_without_enc('wm', 'maxsize', path))
      else
        tk_call_without_enc('wm', 'maxsize', path, *args)
        self
      end
    end

    def minsize(*args)
      if args.size == 0
        list(tk_call_without_enc('wm', 'minsize', path))
      else
        tk_call_without_enc('wm', 'minsize', path, *args)
        self
      end
    end

    def overrideredirect(bool=None)
      if bool == None
        bool(tk_call_without_enc('wm', 'overrideredirect', path))
      else
        tk_call_without_enc('wm', 'overrideredirect', path, bool)
        self
      end
    end

    def positionfrom(who=None)
      if who == None
        r = tk_call_without_enc('wm', 'positionfrom', path)
        (r == "")? nil: r
      else
        tk_call_without_enc('wm', 'positionfrom', path, who)
        self
      end
    end

    def protocol(name=nil, cmd=nil, &b)
      if cmd
        tk_call_without_enc('wm', 'protocol', path, name, cmd)
        self
      elsif b
        tk_call_without_enc('wm', 'protocol', path, name, proc(&b))
        self
      elsif name
        result = tk_call_without_enc('wm', 'protocol', path, name)
        (result == "")? nil : tk_tcl2ruby(result)
      else
        tk_split_simplelist(tk_call_without_enc('wm', 'protocol', path))
      end
    end

    def resizable(*args)
      if args.length == 0
        list(tk_call_without_enc('wm', 'resizable', path)).collect{|e| bool(e)}
      else
        tk_call_without_enc('wm', 'resizable', path, *args)
        self
      end
    end

    def sizefrom(who=None)
      if who == None
        r = tk_call_without_enc('wm', 'sizefrom', path)
        (r == "")? nil: r
      else
        tk_call_without_enc('wm', 'sizefrom', path, who)
        self
      end
    end

    def stackorder
      list(tk_call('wm', 'stackorder', path))
    end

    def stackorder_isabove(win)
      bool(tk_call('wm', 'stackorder', path, 'isabove', win))
    end

    def stackorder_isbelow(win)
      bool(tk_call('wm', 'stackorder', path, 'isbelow', win))
    end

    def state(state=nil)
      if state
        tk_call_without_enc('wm', 'state', path, state)
        self
      else
        tk_call_without_enc('wm', 'state', path)
      end
    end

    def title(str=nil)
      if str
        tk_call('wm', 'title', path, str)
        self
      else
        tk_call('wm', 'title', path)
      end
    end

    def transient(master=nil)
      if master
        tk_call_without_enc('wm', 'transient', path, master)
        self
      else
        window(tk_call_without_enc('wm', 'transient', path))
      end
    end

    def withdraw(ex = true)
      tk_call_without_enc('wm', 'withdraw', path) if ex
      self
    end
  end
end
