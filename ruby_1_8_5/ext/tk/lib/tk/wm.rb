#
# tk/wm.rb : methods for wm command
#
require 'tk'

module Tk
  module Wm
    include TkComm

    TkCommandNames = ['wm'.freeze].freeze

    TOPLEVEL_METHODCALL_OPTKEYS = {}

    def aspect(*args)
      if args.length == 0
        list(tk_call_without_enc('wm', 'aspect', path))
      else
        args = args[0] if args.length == 1 && args[0].kind_of?(Array)
        tk_call('wm', 'aspect', path, *args)
        self
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['aspect'] = 'aspect'

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
    TOPLEVEL_METHODCALL_OPTKEYS['attributes'] = 'attributes'

    def client(name=None)
      if name == None
        tk_call('wm', 'client', path)
      else
        name = '' if name == nil
        tk_call('wm', 'client', path, name)
        self
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['client'] = 'client'

    def colormapwindows(*args)
      if args.size == 0
        list(tk_call_without_enc('wm', 'colormapwindows', path))
      else
        args = args[0] if args.length == 1 && args[0].kind_of?(Array)
        tk_call_without_enc('wm', 'colormapwindows', path, *args)
        self
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['colormapwindows'] = 'colormapwindows'

    def wm_command(value=nil)
      if value
        tk_call('wm', 'command', path, value)
        self
      else
        #procedure(tk_call('wm', 'command', path))
        tk_call('wm', 'command', path)
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['wm_command'] = 'wm_command'

    def deiconify(ex = true)
      if ex
        tk_call_without_enc('wm', 'deiconify', path)
      else
        self.iconify
      end
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
    TOPLEVEL_METHODCALL_OPTKEYS['focusmodel'] = 'focusmodel'

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
    TOPLEVEL_METHODCALL_OPTKEYS['geometry'] = 'geometry'

    def wm_grid(*args)
      if args.size == 0
        list(tk_call_without_enc('wm', 'grid', path))
      else
        args = args[0] if args.length == 1 && args[0].kind_of?(Array)
        tk_call_without_enc('wm', 'grid', path, *args)
        self
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['wm_grid'] = 'wm_grid'

    def group(leader = nil)
      if leader
        tk_call('wm', 'group', path, leader)
        self
      else
        window(tk_call('wm', 'group', path))
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['group'] = 'group'

    def iconbitmap(bmp=nil)
      if bmp
        tk_call_without_enc('wm', 'iconbitmap', path, bmp)
        self
      else
        image_obj(tk_call_without_enc('wm', 'iconbitmap', path))
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['iconbitmap'] = 'iconbitmap'

    def iconphoto(*imgs)
      if imgs.empty?
        @wm_iconphoto = nil unless defined? @wm_iconphoto
        return @wm_iconphoto 
      end

      imgs = imgs[0] if imgs.length == 1 && imgs[0].kind_of?(Array)
      tk_call_without_enc('wm', 'iconphoto', path, *imgs)
      @wm_iconphoto = imgs
      self
    end
    TOPLEVEL_METHODCALL_OPTKEYS['iconphoto'] = 'iconphoto'

    def iconphoto_default(*imgs)
      imgs = imgs[0] if imgs.length == 1 && imgs[0].kind_of?(Array)
      tk_call_without_enc('wm', 'iconphoto', path, '-default', *imgs)
      self
    end

    def iconify(ex = true)
      if ex
        tk_call_without_enc('wm', 'iconify', path)
      else
        self.deiconify
      end
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
    TOPLEVEL_METHODCALL_OPTKEYS['iconmask'] = 'iconmask'

    def iconname(name=nil)
      if name
        tk_call('wm', 'iconname', path, name)
        self
      else
        tk_call('wm', 'iconname', path)
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['iconname'] = 'iconname'

    def iconposition(*args)
      if args.size == 0
        list(tk_call_without_enc('wm', 'iconposition', path))
      else
        args = args[0] if args.length == 1 && args[0].kind_of?(Array)
        tk_call_without_enc('wm', 'iconposition', path, *args)
        self
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['iconposition'] = 'iconposition'

    def iconwindow(win = nil)
      if win
        tk_call_without_enc('wm', 'iconwindow', path, win)
        self
      else
        w = tk_call_without_enc('wm', 'iconwindow', path)
        (w == '')? nil: window(w)
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['iconwindow'] = 'iconwindow'

    def maxsize(*args)
      if args.size == 0
        list(tk_call_without_enc('wm', 'maxsize', path))
      else
        args = args[0] if args.length == 1 && args[0].kind_of?(Array)
        tk_call_without_enc('wm', 'maxsize', path, *args)
        self
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['maxsize'] = 'maxsize'

    def minsize(*args)
      if args.size == 0
        list(tk_call_without_enc('wm', 'minsize', path))
      else
        args = args[0] if args.length == 1 && args[0].kind_of?(Array)
        tk_call_without_enc('wm', 'minsize', path, *args)
        self
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['minsize'] = 'minsize'

    def overrideredirect(mode=None)
      if mode == None
        bool(tk_call_without_enc('wm', 'overrideredirect', path))
      else
        tk_call_without_enc('wm', 'overrideredirect', path, mode)
        self
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['overrideredirect'] = 'overrideredirect'

    def positionfrom(who=None)
      if who == None
        r = tk_call_without_enc('wm', 'positionfrom', path)
        (r == "")? nil: r
      else
        tk_call_without_enc('wm', 'positionfrom', path, who)
        self
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['positionfrom'] = 'positionfrom'

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

    def protocols(kv=nil)
      unless kv
        ret = {}
        self.protocol.each{|name|
          ret[name] = self.protocol(name)
        }
        return ret
      end

      unless kv.kind_of?(Hash)
        fail ArgumentError, 'expect a hash of protocol=>command'
      end
      kv.each{|k, v| self.protocol(k, v)}
      self
    end
    TOPLEVEL_METHODCALL_OPTKEYS['protocols'] = 'protocols'

    def resizable(*args)
      if args.length == 0
        list(tk_call_without_enc('wm', 'resizable', path)).collect{|e| bool(e)}
      else
        args = args[0] if args.length == 1 && args[0].kind_of?(Array)
        tk_call_without_enc('wm', 'resizable', path, *args)
        self
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['resizable'] = 'resizable'

    def sizefrom(who=None)
      if who == None
        r = tk_call_without_enc('wm', 'sizefrom', path)
        (r == "")? nil: r
      else
        tk_call_without_enc('wm', 'sizefrom', path, who)
        self
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['sizefrom'] = 'sizefrom'

    def stackorder
      list(tk_call('wm', 'stackorder', path))
    end

    def stackorder_isabove(win)
      bool(tk_call('wm', 'stackorder', path, 'isabove', win))
    end

    def stackorder_isbelow(win)
      bool(tk_call('wm', 'stackorder', path, 'isbelow', win))
    end

    def state(st=nil)
      if st
        tk_call_without_enc('wm', 'state', path, st)
        self
      else
        tk_call_without_enc('wm', 'state', path)
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['state'] = 'state'

    def title(str=nil)
      if str
        tk_call('wm', 'title', path, str)
        self
      else
        tk_call('wm', 'title', path)
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['title'] = 'title'

    def transient(master=nil)
      if master
        tk_call_without_enc('wm', 'transient', path, master)
        self
      else
        window(tk_call_without_enc('wm', 'transient', path))
      end
    end
    TOPLEVEL_METHODCALL_OPTKEYS['transient'] = 'transient'

    def withdraw(ex = true)
      if ex
        tk_call_without_enc('wm', 'withdraw', path)
      else
        self.deiconify
      end
      self
    end
  end
end
