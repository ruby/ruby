#
#		tk.rb - Tk interface modue using tcltklib
#			$Date$
#			by Yukihiro Matsumoto <matz@netlab.co.jp>

# use Shigehiro's tcltklib
require "tcltklib"
require "tkutil"

module TkComm
  None = Object.new
  def None.to_s
    'None'
  end

  Tk_CMDTBL = {}
  Tk_WINDOWS = {}

  def error_at
    frames = caller(1)
    frames.delete_if do |c|
      c =~ %r!/tk(|core|thcore|canvas|text|entry|scrollbox)\.rb:\d+!
    end
    frames
  end
  private :error_at

  def tk_tcl2ruby(val)
    if val.include? ?\s
      return val.split.collect{|v| tk_tcl2ruby(v)}
    end
    case val
    when /^-?\d+$/
      val.to_i
    when /^\./
      Tk_WINDOWS[val]
    when /^rb_out (c\d+)/
      Tk_CMDTBL[$1]
    when / /
      val.split.collect{|elt|
	tk_tcl2ruby(elt)
      }
    when /^-?\d+\.\d*$/
      val.to_f
    else
      val
    end
  end

  def tk_split_list(str)
    return [] if str == ""
    idx = str.index('{')
    return tk_tcl2ruby(str) unless idx

    list = tk_tcl2ruby(str[0,idx])
    str = str[idx+1..-1]
    i = -1
    brace = 1
    str.each_byte {|c|
      i += 1
      brace += 1 if c == ?{
      brace -= 1 if c == ?}
      break if brace == 0
    }
    if str[0, i] == ' '
      list.push ' '
    else
      list.push tk_split_list(str[0, i])
    end
    list += tk_split_list(str[i+1..-1])
    list
  end
  private :tk_tcl2ruby, :tk_split_list

  def hash_kv(keys)
    conf = []
    if keys and keys != None
      for k, v in keys
	 conf.push("-#{k}")
	 v = install_cmd(v) if v.kind_of? Proc
	 conf.push(v)
      end
    end
    conf
  end
  private :hash_kv

  def bool(val)
    case val
    when "1", 1, 'yes', 'true'
      TRUE
    else
      FALSE
    end
  end
  def number(val)
    case val
    when /^-?\d+$/
      val.to_i
    when /^-?\d+\.\d*$/
      val.to_f
    else
      val
    end
  end
  def string(val)
    if val == "{}"
      ''
    elsif val[0] == ?{
      val[1..-2]
    else
      val
    end
  end
  def list(val)
    tk_split_list(val).to_a
  end
  def window(val)
    Tk_WINDOWS[val]
  end
  def procedure(val)
    if val =~ /^rb_out (c\d+)/
      Tk_CMDTBL[$1]
    else
      nil
    end
  end
  private :bool, :number, :string, :list, :window, :procedure

  Tk_IDs = [0]		# [0]-cmdid, [1]-winid
  def _curr_cmd_id
    id = format("c%.4d", Tk_IDs[0])
  end
  def _next_cmd_id
    id = _curr_cmd_id
    Tk_IDs[0] += 1
  end
  def install_cmd(cmd)
    return '' if cmd == ''
    id = _next_cmd_id
    Tk_CMDTBL[id] = cmd
    @cmdtbl = [] if not @cmdtbl
    @cmdtbl.push id
    return format("rb_out %s", id);
  end
  def uninstall_cmd(id)
    Tk_CMDTBL[id] = nil
  end
  private :install_cmd, :uninstall_cmd

  def install_win(ppath)
    id = format("w%.4d", Tk_IDs[0])
    Tk_IDs[0] += 1
    if !ppath or ppath == "."
      @path = format(".%s", id);
    else
      @path = format("%s.%s", ppath, id)
    end
    Tk_WINDOWS[@path] = self
  end

  def uninstall_win()
    Tk_WINDOWS[@path] = nil
  end

  class Event
    def initialize(seq,b,f,h,k,s,t,w,x,y,aa,ee,kk,nn,ww,tt,xx,yy)
      @serial = seq
      @num = b
      @focus = (f == 1)
      @height = h
      @keycode = k
      @state = s
      @time = t
      @width = w
      @x = x
      @y = y
      @char = aa
      @send_event = (ee == 1)
      @keysym = kk
      @keysym_num = nn
      @type = tt
      @widget = ww
      @x_root = xx
      @y_root = yy
    end
    attr :serial
    attr :num
    attr :focus
    attr :height
    attr :keycode
    attr :state
    attr :time
    attr :width
    attr :x
    attr :y
    attr :char
    attr :send_event
    attr :keysym
    attr :keysym_num
    attr :type
    attr :widget
    attr :x_root
    attr :y_root
  end

  def install_bind(cmd, args=nil)
    if args
      id = install_cmd(proc{|arg|
	TkUtil.eval_cmd cmd, *arg
      })
      id + " " + args
    else
      id = install_cmd(proc{|arg|
	TkUtil.eval_cmd cmd, Event.new(*arg)
      })
      id + ' %# %b %f %h %k %s %t %w %x %y %A %E %K %N %W %T %X %Y'
    end
  end

  def _bind(path, context, cmd, args=nil)
    begin
      id = install_bind(cmd, args)
      tk_call 'bind', path, "<#{context}>", id
    rescue
      uninstall_cmd(id)
      fail
    end
  end
  private :install_bind, :_bind

  def bind_all(context, cmd=Proc.new, args=nil)
    _bind 'all', context, cmd, args
  end

  def pack(*args)
    TkPack.configure *args
  end

  def after(ms, cmd=Proc.new)
    myid = _curr_cmd_id
    tk_call 'after', ms,
      install_cmd(proc{
		    TkUtil.eval_cmd cmd
		    uninstall_cmd myid
		  })
  end

  def update(idle=nil)
    if idle
      tk_call 'update', 'idletasks'
    else
      tk_call 'update'
    end
  end

end

module TkCore
  include TkComm
  extend TkComm

  INTERP = TclTkIp.new
  INTERP._invoke("proc", "rb_out", "args", "ruby [format \"TkCore.callback %%Q!%s!\" $args]")

  def TkCore.callback(arg)
    arg = Array(tk_split_list(arg))
    TkUtil.eval_cmd Tk_CMDTBL[arg.shift], *arg
  end

  def mainloop
    TclTkLib.mainloop
  end

  def _get_eval_string(str)
    return nil if str == None
    if str.kind_of?(Hash)
      str = hash_kv(str).join(" ")
    elsif str == nil
      str = ""
    elsif str == false
      str = "0"
    elsif str == true
      str = "1"
    elsif (str.respond_to?(:to_eval))
      str = str.to_eval()
    else
      str = str.to_s()
    end
    return str
  end

  def tk_call(*args)
    print args.join(" "), "\n" if $DEBUG
    args.filter {|x|_get_eval_string(x)}
    args.compact!
    args.flatten!
    begin
      res = INTERP._invoke(*args)
    rescue NameError
      err = $!
      begin
        args.unshift "unknown"
        res = INTERP._invoke(*args)
      rescue
	raise unless /^invalid command/ =~ $!
	raise err
      end
    end
    if  INTERP._return_value() != 0
      fail RuntimeError, res, error_at
    end
    print "==> ", res, "\n" if $DEBUG
    return res
  end
end

module Tk
  include TkCore
  extend Tk

  def root
    TkRoot.new
  end

  def bell
    tk_call 'bell'
  end

  module Scrollable
    def xscrollcommand(cmd=Proc.new)
      configure_cmd 'xscrollcommand', cmd
    end
    def yscrollcommand(cmd=Proc.new)
      configure_cmd 'yscrollcommand', cmd
    end
  end

  module Wm
    def aspect(*args)
      w = window(tk_call('wm', 'grid', path, *args))
      w.split.collect{|s|s.to_i} if args.length == 0
    end
    def client(name=None)
      tk_call 'wm', 'client', path, name
    end
    def colormapwindows(*args)
      list(tk_call('wm', 'colormapwindows', path, *args))
    end
    def wm_command(value=None)
      string(tk_call('wm', 'command', path, value))
    end
    def deiconify
      tk_call 'wm', 'deiconify', path
    end
    def focusmodel(*args)
      tk_call 'wm', 'focusmodel', path, *args
    end
    def frame
      tk_call 'wm', 'frame', path
    end
    def geometry(*args)
      list(tk_call('wm', 'geometry', path, *args))
    end
    def grid(*args)
      w = tk_call('wm', 'grid', path, *args)
      list(w) if args.size == 0
    end
    def group(*args)
      tk_call 'wm', 'path', path, *args
    end
    def iconbitmap(*args)
      tk_call 'wm', 'bitmap', path, *args
    end
    def iconify
      tk_call 'wm', 'iconify', path
    end
    def iconmask(*args)
      tk_call 'wm', 'iconmask', path, *args
    end
    def iconname(*args)
      tk_call 'wm', 'iconname', path, *args
    end
    def iconposition(*args)
      w = tk_call('wm', 'iconposition', path, *args)
      list(w) if args.size == 0
    end
    def iconwindow(*args)
      w = tk_call('wm', 'iconwindow', path, *args)
      window(w) if args.size == 0
    end
    def maxsize(*args)
      w = tk_call('wm', 'maxsize', path, *args)
      list(w) if not args.size == 0
    end
    def minsize(*args)
      w = tk_call('wm', 'minsize', path, *args)
      list(w) if args.size == 0
    end
    def overrideredirect(bool=None)
      if bool == None
	bool(tk_call('wm', 'overrideredirect', path))
      else
	tk_call 'wm', 'overrideredirect', path, bool
      end
    end
    def positionfrom(*args)
      tk_call 'wm', 'positionfrom', path, *args
    end
    def protocol(name, func=None)
      func = install_cmd(func) if not func == None
      tk_call 'wm', 'command', path, name, func
    end
    def resizable(*args)
      w = tk_call('wm', 'resizable', path, *args)
      if args.length == 0
	list(w).collect{|e| bool(e)}
      end
    end
    def sizefrom(*args)
      list(tk_call('wm', 'sizefrom', path, *args))
    end
    def state
      tk_call 'wm', 'state', path
    end
    def title(*args)
      tk_call 'wm', 'title', path, *args
    end
    def transient(*args)
      tk_call 'wm', 'transient', path, *args
    end
    def withdraw
      tk_call 'wm', 'withdraw', path
    end
  end
end

class TkVariable
  include Tk

  Tk_VARIABLE_ID = ["v00000"]
  def initialize(val="")
    @id = Tk_VARIABLE_ID[0]
    Tk_VARIABLE_ID[0] = Tk_VARIABLE_ID[0].succ
    s = '"' + _get_eval_string(val).gsub(/[][$"]/, '\\\\\&') + '"' #'
    INTERP._eval(format('global %s; set %s %s', @id, @id, s))
  end

  def id
    @id
  end

  def value
    INTERP._eval(format('global %s; set %s', @id, @id))
  end

  def value=(val)
    INTERP._eval(format('global %s; set %s %s', @id, @id, _get_eval_string(val)))
  end

  def to_i
    Integer(number(value))
  end

  def to_f
    Float(number(value))
  end

  def to_s
    String(string(value))
  end

  def inspect
    format "<TkVariable: %s>", @id
  end

  def ==(other)
    case other
    when TkVariable
      self.equal(self)
    when String
      self.to_s == other
    when Integer
      self.to_i == other
    when Float
      self.to_f == other
    when Array
      self.to_a == other
    else
      false
    end
  end

  def to_a
    list(value)
  end

  def to_eval
    @id
  end
end

module TkSelection
  include Tk
  extend Tk
  def clear(win=Tk.root)
    tk_call 'selection', 'clear', win.path
  end
  def get(type=None)
    tk_call 'selection', 'get', type
  end
  def TkSelection.handle(win, func, type=None, format=None)
    id = install_cmd(func)
    tk_call 'selection', 'handle', win.path, id, type, format
  end
  def handle(func, type=None, format=None)
    TkSelection.handle self, func, type, format
  end
  def TkSelection.own(win, func=None)
    id = install_cmd(func)
    tk_call 'selection', 'own', win.path, id
  end
  def own(func=None)
    TkSelection.own self, func
  end

  module_function :clear, :get
end

module TkWinfo
  include Tk
  extend Tk
  def TkWinfo.atom(name)
    tk_call 'winfo', name
  end
  def winfo_atom(name)
    TkWinfo.atom name
  end
  def TkWinfo.atomname(id)
    tk_call 'winfo', id
  end
  def winfo_atomname(id)
    TkWinfo.atomname id
  end
  def TkWinfo.cells(window)
    number(tk_call('winfo', window.path))
  end
  def winfo_cells
    TkWinfo.cells self
  end
  def TkWinfo.children(window)
    c = tk_call('winfo', 'children', window.path)
    list(c)
  end
  def winfo_children
    TkWinfo.children self
  end
  def TkWinfo.classname(window)
    tk_call 'winfo', 'class', window.path
  end
  def winfo_classname
    TkWinfo.classname self
  end
  def TkWinfo.containing(rootX, rootY)
    path = tk_call('winfo', 'class', window.path)
    window(path)
  end
  def winfo_containing(x, y)
    TkWinfo.containing x, y
  end
  def TkWinfo.depth(window)
    number(tk_call('winfo', 'depth', window.path))
  end
  def winfo_depth(window)
    TkWinfo.depth self
  end
  def TkWinfo.exist?(window)
    bool(tk_call('winfo', 'exists', window.path))
  end
  def winfo_exist?(window)
    TkWinfo.exist? self
  end
  def TkWinfo.fpixels(window, number)
    number(tk_call('winfo', 'fpixels', window.path, number))
  end
  def winfo_fpixels(window, number)
    TkWinfo.fpixels self
  end
  def TkWinfo.geometry(window)
    list(tk_call('winfo', 'geometry', window.path))
  end
  def winfo_geometry(window)
    TkWinfo.geometry self
  end
  def TkWinfo.height(window)
    number(tk_call('winfo', 'height', window.path))
  end
  def winfo_height(window)
    TkWinfo.height self
  end
  def TkWinfo.id(window)
    number(tk_call('winfo', 'id', window.path))
  end
  def winfo_id(window)
    TkWinfo.id self
  end
  def TkWinfo.mapped?(window)
    bool(tk_call('winfo', 'ismapped', window.path))
  end
  def winfo_mapped?(window)
    TkWinfo.mapped? self
  end
  def TkWinfo.parent(window)
    window(tk_call('winfo', 'parent', window.path))
  end
  def winfo_parent(window)
    TkWinfo.parent self
  end
  def TkWinfo.widget(id)
    window(tk_call('winfo', 'pathname', id))
  end
  def winfo_widget(id)
    TkWinfo.widget id
  end
  def TkWinfo.pixels(window, number)
    number(tk_call('winfo', 'pixels', window.path, number))
  end
  def winfo_pixels(window, number)
    TkWinfo.pixels self, number
  end
  def TkWinfo.reqheight(window)
    number(tk_call('winfo', 'reqheight', window.path))
  end
  def winfo_reqheight(window)
    TkWinfo.reqheight self
  end
  def TkWinfo.reqwidth(window)
    number(tk_call('winfo', 'reqwidth', window.path))
  end
  def winfo_reqwidth(window)
    TkWinfo.reqwidth self
  end
  def TkWinfo.rgb(window, color)
    list(tk_call('winfo', 'rgb', window.path, color))
  end
  def winfo_rgb(window, color)
    TkWinfo.rgb self, color
  end
  def TkWinfo.rootx(window)
    number(tk_call('winfo', 'rootx', window.path))
  end
  def winfo_rootx(window)
    TkWinfo.rootx self
  end
  def TkWinfo.rooty(window)
    number(tk_call('winfo', 'rooty', window.path))
  end
  def winfo_rooty(window)
    TkWinfo.rooty self
  end
  def TkWinfo.screen(window)
    tk_call 'winfo', 'screen', window.path
  end
  def winfo_screen(window)
    TkWinfo.screen self
  end
  def TkWinfo.screencells(window)
    number(tk_call('winfo', 'screencells', window.path))
  end
  def winfo_screencells(window)
    TkWinfo.screencells self
  end
  def TkWinfo.screendepth(window)
    number(tk_call('winfo', 'screendepth', window.path))
  end
  def winfo_screendepth(window)
    TkWinfo.screendepth self
  end
  def TkWinfo.screenheight (window)
    number(tk_call('winfo', 'screenheight', window.path))
  end
  def winfo_screenheight(window)
    TkWinfo.screenheight self
  end
  def TkWinfo.screenmmheight(window)
    number(tk_call('winfo', 'screenmmheight', window.path))
  end
  def winfo_screenmmheight(window)
    TkWinfo.screenmmheight self
  end
  def TkWinfo.screenmmwidth(window)
    number(tk_call('winfo', 'screenmmwidth', window.path))
  end
  def winfo_screenmmwidth(window)
    TkWinfo.screenmmwidth self
  end
  def TkWinfo.screenvisual(window)
    tk_call 'winfo', 'screenvisual', window.path
  end
  def winfo_screenvisual(window)
    TkWinfo.screenvisual self
  end
  def TkWinfo.screenwidth(window)
    number(tk_call('winfo', 'screenwidth', window.path))
  end
  def winfo_screenwidth(window)
    TkWinfo.screenwidth self
  end
  def TkWinfo.toplevel(window)
    window(tk_call('winfo', 'toplevel', window.path))
  end
  def winfo_toplevel(window)
    TkWinfo.toplevel self
  end
  def TkWinfo.visual(window)
    tk_call 'winfo', 'visual', window.path
  end
  def winfo_visual(window)
    TkWinfo.visual self
  end
  def TkWinfo.vrootheigh(window)
    number(tk_call('winfo', 'vrootheight', window.path))
  end
  def winfo_vrootheight(window)
    TkWinfo.vrootheight self
  end
  def TkWinfo.vrootwidth(window)
    number(tk_call('winfo', 'vrootwidth', window.path))
  end
  def winfo_vrootwidth(window)
    TkWinfo.vrootwidth self
  end
  def TkWinfo.vrootx(window)
    number(tk_call('winfo', 'vrootx', window.path))
  end
  def winfo_vrootx(window)
    TkWinfo.vrootx self
  end
  def TkWinfo.vrooty(window)
    number(tk_call('winfo', 'vrooty', window.path))
  end
  def winfo_vrooty(window)
    TkWinfo.vrooty self
  end
  def TkWinfo.width(window)
    number(tk_call('winfo', 'width', window.path))
  end
  def winfo_width(window)
    TkWinfo.width self
  end
  def TkWinfo.x(window)
    number(tk_call('winfo', 'x', window.path))
  end
  def winfo_x(window)
    TkWinfo.x self
  end
  def TkWinfo.y(window)
    number(tk_call('winfo', 'y', window.path))
  end
  def winfo_y(window)
    TkWinfo.y self
  end
end

module TkPack
  include Tk
  extend Tk
  def configure(win, *args)
    if args[-1].kind_of?(Hash)
      keys = args.pop
    end
    wins = [win.epath]
    for i in args
      wins.push i.epath
    end
    tk_call "pack", 'configure', *(wins+hash_kv(keys))
  end

  def forget(*args)
    tk_call 'pack', 'forget' *args
  end

  def propagate(master, bool=None)
    bool(tk_call('pack', 'propagate', master.epath, bool))
  end
  module_function :configure, :forget, :propagate
end

module TkOption
  include Tk
  extend Tk
  def add pat, value, pri=None
    tk_call 'option', 'add', pat, value, pri
  end
  def clear
    tk_call 'option', 'clear'
  end
  def get win, classname, name
    tk_call 'option', 'get', classname, name
  end
  def readfile file, pri=None
    tk_call 'option', 'readfile', file, pri
  end
  module_function :add, :clear, :get, :readfile
end

class TkObject<TkKernel
  include Tk

  def path
    return @path
  end

  def epath
    return @path
  end

  def to_eval
    @path
  end

  def tk_send(cmd, *rest)
    tk_call path, cmd, *rest
  end
  private :tk_send

  def method_missing(id, *args)
    if (args.length == 1)
      configure id.id2name, args[0]
    else
      $@ = error_at
      super
    end
  end

  def []=(id, val)
    configure id, val
  end

  def configure(slot, value)
    if value == FALSE
      value = "0"
    elsif value.kind_of? Proc
      value = install_cmd(value)
    end
    tk_call path, 'configure', "-#{slot}", value
  end

  def configure_cmd(slot, value)
    configure slot, install_cmd(value)
  end

  def bind(context, cmd=Proc.new, args=nil)
    _bind path, context, cmd, args
  end

  def tk_trace_variable(v)
    unless v.kind_of?(TkVariable)
      fail ArgumentError, format("requires TkVariable given %s", v.type)
    end
    v
  end
  private :tk_trace_variable

  def destroy
    tk_call 'trace', 'vdelete', @tk_vn, 'w', @var_id if @var_id
  end
end

class TkWindow<TkObject

  def initialize(parent=nil, keys=nil)
    install_win(if parent then parent.path end)
    create_self
    if keys
      tk_call @path, 'configure', *hash_kv(keys)
    end
  end

  def create_self
  end
  private :create_self

  def pack(keys = nil)
    tk_call 'pack', epath, *hash_kv(keys)
    self
  end

  def unpack(keys = nil)
    tk_call 'pack', 'forget', epath
    self
  end

  def place(keys = nil)
    tk_call 'place', epath, *hash_kv(keys)
    self
  end

  def unplace(keys = nil)
    tk_call 'place', 'forget', epath, *hash_kv(keys)
    self
  end
  alias place_forget unplace

  def place_config(keys)
    tk_call "place", 'configure', epath, *hash_kv(keys)
  end

  def place_info()
    ilist = list(tk_call('place', 'info', epath))
    info = {}
    while key = ilist.shift
      info[key[1..-1]] = ilist.shift
    end
    return info
  end

  def pack_slaves()
    list(tk_call('pack', 'slaves', epath))
  end

  def pack_info()
    ilist = list(tk_call('pack', 'info', epath))
    info = {}
    while key = ilist.shift
      info[key[1..-1]] = ilist.shift
    end
    return info
  end

  def place_slaves()
    list(tk_call('place', 'slaves', epath))
  end

  def focus
    tk_call 'focus', path
    self
  end

  def grab(*args)
    if !args or args.length == 0
      tk_call 'grab', 'set', path
    elsif args.length == 1
      case args[0]
      when 'global'
	tk_call 'grab', 'set', '-global', path
      else
	val = tk_call('grab', arg[0], path)
      end
      case args[0]
      when 'current'
	return window(val)
      when 'status'
	return val
      end
    else
      fail ArgumentError, 'wrong # of args'
    end
  end

  def lower(below=None)
    tk_call 'lower', path, below
    self
  end
  def raise(above=None)
    tk_call 'raise', path, above
    self
  end

  def command(cmd=Proc.new)
    configure_cmd 'command', cmd
  end

  def colormodel model=None
    tk_call 'tk', 'colormodel', path, model
    self
  end

  def destroy
    tk_call 'destroy', path
    if @cmdtbl
      for id in @cmdtbl
	uninstall_cmd id
      end
    end
    uninstall_win
  end
end

class TkRoot<TkWindow
  include Wm
  ROOT = []
  def TkRoot.new
    return ROOT[0] if ROOT[0]
    new = super
    ROOT[0] = new
    Tk_WINDOWS["."] = new
  end
  def create_self
    @path = '.'
  end
  def path
    "."
  end
end

class TkToplevel<TkWindow
  include Wm
  def initialize(parent=nil, screen=nil, classname=nil, keys=nil)
    @screen = screen if screen
    @classname = classname if classname
    super(parent, keys)
  end

  def create_self
    s = []
    s.push "-screen #@screen" if @screen 
    s.push "-class #@classname" if @classname
    tk_call 'toplevel', path, *s
  end
end

class TkFrame<TkWindow
  def create_self
    tk_call 'frame', @path
  end
end

class TkLabel<TkWindow
  def create_self
    tk_call 'label', @path
  end
  def textvariable(v)
    configure 'textvariable', tk_trace_variable(v)
  end
end

class TkButton<TkLabel
  def create_self
    tk_call 'button', @path
  end
  def invoke
    tk_send 'invoke'
  end
  def flash
    tk_send 'flash'
  end
end

class TkRadioButton<TkButton
  def create_self
    tk_call 'radiobutton', @path
  end
  def deselect
    tk_send 'deselect'
  end
  def select
    tk_send 'select'
  end
  def variable(v)
    configure 'variable', tk_trace_variable(v)
  end
end

class TkCheckButton<TkRadioButton
  def create_self
    tk_call 'checkbutton', @path
  end
  def toggle
    tk_send 'toggle'
  end
end

class TkMessage<TkLabel
  def create_self
    tk_call 'message', @path
  end
end

class TkScale<TkWindow
  def create_self
    tk_call 'scale', path
  end

  def get
    number(tk_send('get'))
  end

  def set(val)
    tk_send "set", val
  end

  def value
    get
  end

  def value= (val)
    set val
  end
end

class TkScrollbar<TkWindow
  def create_self
    tk_call 'scrollbar', path
  end

  def delta(deltax=None, deltay=None)
    number(tk_send('delta', deltax, deltay))
  end

  def fraction(x=None, y=None)
    number(tk_send('fraction', x, y))
  end

  def identify(x=None, y=None)
    tk_send('fraction', x, y)
  end

  def get
    ary1 = tk_send('get', path).split
    ary2 = []
    for i in ary1
      ary2.push number(i)
    end
    ary2
  end

  def set(first, last)
    tk_send "set", first, last
  end
end

class TkTextWin<TkWindow
  def bbox(index)
    tk_send 'bbox', index
  end
  def delete(first, last=None)
    tk_send 'delete', first, last
  end
  def get(*index)
    tk_send 'get', *index
  end
  def index(index)
    tk_send 'index', index
  end
  def insert(index, chars, *args)
    tk_send 'insert', index, chars, *args
  end
  def scan_mark(x, y)
    tk_send 'scan', 'mark', x, y
  end
  def scan_dragto(x, y)
    tk_send 'scan', 'dragto', x, y
  end
  def see(index)
    tk_send 'see', index
  end
end

class TkListbox<TkTextWin
  def create_self
    tk_call 'listbox', path
  end

  def activate(y)
    tk_send 'activate', y
  end
  def curselection
    list(tk_send('curselection'))
  end
  def nearest(y)
    tk_send('nearest', y).to_i
  end
  def size(y)
    tk_send('size').to_i
  end
  def selection_anchor(index)
    tk_send 'selection', 'anchor', index
  end
  def selection_clear(first, last=None)
    tk_send 'selection', 'clear', first, last
  end
  def selection_includes
    bool(tk_send('selection', 'includes'))
  end
  def selection_set(first, last=None)
    tk_send 'selection', 'set', first, last
  end
  def xview(cmd, index, *more)
    v = tk_send('xview', cmd, index, *more)
    v.to_i if more.size == 0
  end
  def yview(cmd, index, *more)
    v = tk_send('yview', cmd, index, *more)
    v.to_i if more.size == 0
  end
end

class TkMenu<TkWindow
  def create_self
    tk_call 'menu', path
  end
  def activate(index)
    tk_send 'activate', index
  end
  def add(type, keys=nil)
    tk_send 'add', type, *hash_kv(keys)
  end
  def index(index)
    tk_send 'index', index
  end
  def invoke
    tk_send 'invoke'
  end
  def insert(index, type, *keys)
    tk_send 'add', index, type, *hash_kv(keys)
  end
  def post(x, y)
    tk_send 'post', x, y
  end
  def postcascade(index)
    tk_send 'postcascade', index
  end
  def postcommand(cmd=Proc.new)
    configure_cmd 'postcommand', cmd
  end
  def menutype(index)
    tk_send 'type', index
  end
  def unpost
    tk_send 'unpost'
  end
  def yposition(index)
    number(tk_send('yposition', index))
  end
end

class TkMenubutton<TkLabel
  def create_self
    tk_call 'menubutton', path
  end
end

module TkComposite
  def initialize(parent=nil, *args)
    @frame = TkFrame.new(parent)
    @path = @epath = @frame.path
    initialize_composite(*args)
  end

  def epath
    @epath
  end

  def initialize_composite(*args) end
  private :initialize_composite

  def delegate(option, *wins)
    unless @delegates
      @delegates = {} 
      @delegates['DEFAULT'] = @frame
    end
    if @delegates[option].kind_of?(Array)
      for i in wins
	@delegates[option].push(i)
      end
    else
      @delegates[option] = wins
    end
  end

  def configure(slot, value)
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

autoload :TkCanvas, 'tkcanvas'
autoload :TkImage, 'tkcanvas'
autoload :TkBitmapImage, 'tkcanvas'
autoload :TkPhotoImage, 'tkcanvas'
autoload :TkEntry, 'tkentry'
autoload :TkText, 'tktext'
autoload :TkDialog, 'tkdialog'
autoload :TkMenubar, 'tkmenubar'
