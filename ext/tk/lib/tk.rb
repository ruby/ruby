#
#		tk.rb - Tk interface modue using tcltklib
#			$Date$
#			by Yukihiro Matsumoto <matz@netlab.co.jp>

# use Shigehiro's tcltklib
require "tcltklib"
require "tkutil"

module TkComm
  WidgetClassNames = {}

  None = Object.new
  def None.to_s
    'None'
  end

  Tk_CMDTBL = {}
  Tk_WINDOWS = {}

  def error_at
    frames = caller()
    frames.delete_if do |c|
      c =~ %r!/tk(|core|thcore|canvas|text|entry|scrollbox)\.rb:\d+!
    end
    frames
  end
  private :error_at

  def _genobj_for_tkwidget(path)
    return TkRoot.new if path == '.'

    begin
      tk_class = TkCore::INTERP._invoke('winfo', 'class', path)
    rescue
      return path
    end

    ruby_class = WidgetClassNames[tk_class]
    gen_class_name = ruby_class.name + 'GeneratedOnTk'
    unless Object.const_defined? gen_class_name
      eval "class #{gen_class_name}<#{ruby_class.name}
              def initialize(path)
                @path=path
                Tk_WINDOWS[@path] = self
              end
            end"
    end
    eval "#{gen_class_name}.new('#{path}')"
  end

  def tk_tcl2ruby(val)
    if val =~ /^rb_out (c\d+)/
      return Tk_CMDTBL[$1]
    end
    if val.include? ?\s
      return val.split.collect{|v| tk_tcl2ruby(v)}
    end
    case val
    when /^@font/
      TkFont.get_obj(val)
    when /^-?\d+$/
      val.to_i
    when /^\./
      Tk_WINDOWS[val] ? Tk_WINDOWS[val] : _genobj_for_tkwidget(val)
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
    list = [] if list == ""
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

  def tk_split_simplelist(str)
    return [] if str == ""
    idx = str.index('{')
    return str.split unless idx

    list = str[0,idx].split
    str = str[idx+1..-1]
    i = -1
    brace = 1
    str.each_byte {|c|
      i += 1
      brace += 1 if c == ?{
      brace -= 1 if c == ?}
      break if brace == 0
    }
    if i == 0
      list.push ''
    elsif str[0, i] == ' '
      list.push ' '
    else
      list.push str[0..i-1]
    end
    list += tk_split_simplelist(str[i+1..-1])
    list
  end
  private :tk_tcl2ruby, :tk_split_list, :tk_split_simplelist

  def hash_kv(keys)
    conf = []
    if keys and keys != None
      for k, v in keys
	 conf.push("-#{k}")
	 conf.push(v)
      end
    end
    conf
  end
  private :hash_kv

  def array2tk_list(ary)
    ary.collect{|e|
      if e.kind_of? Array
	"{#{array2tk_list(e)}}"
      elsif e.kind_of? Hash
	"{#{e.to_a.collect{|ee| array2tk_list(ee)}.join(' ')}}"
      else
	s = _get_eval_string(e)
	(s.index(/\s/))? "{#{s}}": s
      end
    }.join(" ")
  end
  private :array2tk_list

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

  def _get_eval_string(str)
    return nil if str == None
    if str.kind_of?(String)
      # do nothing
    elsif str.kind_of?(Hash)
      str = hash_kv(str).join(" ")
    elsif str.kind_of?(Array)
      str = array2tk_list(str)
    elsif str.kind_of?(Proc)
      str = install_cmd(str)
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
  private :_get_eval_string

  def ruby2tcl(v)
    if v.kind_of?(Hash)
      v = hash_kv(v)
      v.flatten!
      v.collect{|e|ruby2tcl(e)}
    else
      _get_eval_string(v)
    end
  end
  private :ruby2tcl

  Tk_IDs = [0, 0]		# [0]-cmdid, [1]-winid
  def _curr_cmd_id
    id = format("c%.4d", Tk_IDs[0])
  end
  def _next_cmd_id
    id = _curr_cmd_id
    Tk_IDs[0] += 1
    id
  end
  def install_cmd(cmd)
    return '' if cmd == ''
    id = _next_cmd_id
    Tk_CMDTBL[id] = cmd
    @cmdtbl = [] unless @cmdtbl
    @cmdtbl.push id
    return format("rb_out %s", id);
  end
  def uninstall_cmd(id)
    id = $1 if /rb_out (c\d+)/ =~ id
    Tk_CMDTBL[id] = nil
  end
  private :install_cmd, :uninstall_cmd

  def install_win(ppath)
    id = format("w%.4d", Tk_IDs[1])
    Tk_IDs[1] += 1
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

  def tk_event_sequence(context)
    if context.kind_of? TkVirtualEvent
      context = context.path
    end
    if context.kind_of? Array
      context = context.collect{|ev|
	if context.kind_of? TkVirtualEvent
	  ev.path
	else
	  ev
	end
      }.join("><")
    end
    if /,/ =~ context
      context = context.split(/\s*,\s*/).join("><")
    else
      context
    end
  end

  def _bind_core(mode, what, context, cmd, args=nil)
    id = install_bind(cmd, args) if cmd
    begin
      tk_call(*(what + ["<#{tk_event_sequence(context)}>", mode + id]))
    rescue
      uninstall_cmd(id) if cmd
      fail
    end
  end

  def _bind(what, context, cmd, args=nil)
    _bind_core('', what, context, cmd, args)
  end

  def _bind_append(what, context, cmd, args=nil)
    _bind_core('+', what, context, cmd, args)
  end

  def _bind_remove(what, context)
    tk_call(*(what + ["<#{tk_event_sequence(context)}>", '']))
  end

  def _bindinfo(what, context=nil)
    if context
      tk_call(*what+["<#{tk_event_sequence(context)}>"]).collect {|cmdline|
	if cmdline =~ /^rb_out (c\d+)\s+(.*)$/
	  [Tk_CMDTBL[$1], $2]
	else
	  cmdline
	end
      }
    else
      tk_split_list(tk_call(*what)).collect{|seq|
	seq[1..-2].gsub(/></,',')
      }
    end
  end
  private :install_bind, :tk_event_sequence, 
          :_bind_core, :_bind, :_bind_append, :_bind_remove, :_bindinfo

  def bind(tagOrClass, context, cmd=Proc.new, args=nil)
    _bind(["bind", tagOrClass], context, cmd, args)
  end

  def bind_append(tagOrClass, context, cmd=Proc.new, args=nil)
    _bind_append(["bind", tagOrClass], context, cmd, args)
  end

  def bind_remove(tagOrClass, context)
    _bind_remove(['bind', tagOrClass], context)
  end

  def bindinfo(tagOrClass, context=nil)
    _bindinfo(['bind', tagOrClass], context)
  end

  def bind_all(context, cmd=Proc.new, args=nil)
    _bind(['bind', 'all'], context, cmd, args)
  end

  def bind_append_all(context, cmd=Proc.new, args=nil)
    _bind_append(['bind', 'all'], context, cmd, args)
  end

  def bindinfo_all(context=nil)
    _bindinfo(['bind', 'all'], context)
  end

  def pack(*args)
    TkPack.configure *args
  end

  def grid(*args)
    TkGrid.configure *args
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

  INTERP._invoke("proc", "rb_out", "args", "if {[set st [catch {ruby [format \"TkCore.callback %%Q!%s!\" $args]} ret]] != 0} {if {[regsub -all {!} $args {\\!} newargs] == 0} {return -code $st $ret} {if {[set st [catch {ruby [format \"TkCore.callback %%Q!%s!\" $newargs]} ret]] != 0} {return -code $st $ret} {return $ret}}} {return $ret}")

  def callback_break
    fail TkCallbackBreak, "Tk callback returns 'break' status"
  end

  def callback_continue
    fail TkCallbackContinue, "Tk callback returns 'continue' status"
  end

  def after(ms, cmd=Proc.new)
    myid = _curr_cmd_id
    cmdid = install_cmd(cmd)
    tk_call("after",ms,cmdid)
    return
    if false #defined? Thread
      Thread.start do
	ms = Float(ms)/1000
	ms = 10 if ms == 0
	sleep ms/1000
	cmd.call
      end
    else
      cmdid = install_cmd(cmd)
      tk_call("after",ms,cmdid)
    end
  end

  def TkCore.callback(arg)
    arg = Array(tk_split_list(arg))
    _get_eval_string(TkUtil.eval_cmd(Tk_CMDTBL[arg.shift], *arg))
  end

  def scaling(scale=nil)
    if scale
      tk_call('tk', 'scaling', scale)
    else
      Float(number(tk_call('tk', 'scaling')))
    end
  end
  def scaling_displayof(win, scale=nil)
    if scale
      tk_call('tk', 'scaling', '-displayof', win, scale)
    else
      Float(number(tk_call('tk', '-displayof', win, 'scaling')))
    end
  end

  def appname(name=None)
    tk_call('tk', 'appname', name)
  end

  def appsend(interp, async, *args)
    if async
      tk_call('send', '-async', '--', interp, *args)
    else
      tk_call('send', '--', interp, *args)
    end
  end

  def rb_appsend(interp, async, *args)
    args = args.filter{|c| _get_eval_string(c).gsub(/[][$"]/, '\\\\\&')}
    args.push(').to_s"')
    appsend(interp, async, 'ruby "(', *args)
  end

  def appsend_displayof(interp, win, async, *args)
    win = '.' if win == nil
    if async
      tk_call('send', '-async', '-displayof', win, '--', interp, *args)
    else
      tk_call('send', '-displayor', win, '--', interp, *args)
    end
  end

  def rb_appsend_displayof(interp, win, async, *args)
    args = args.filter{|c| _get_eval_string(c).gsub(/[][$"]/, '\\\\\&')}
    args.push(').to_s"')
    appsend_displayof(interp, win, async, 'ruby "(', *args)
  end

  def info(*args)
    tk_call('info', *args)
  end

  def mainloop
    TclTkLib.mainloop
  end

  def event_generate(window, context, keys=nil)
    window = window.path if window.kind_of? TkObject
    if keys
      tk_call('event', 'generate', window, 
	      "<#{tk_event_sequence(context)}>", *hash_kv(keys))
    else
      tk_call('event', 'generate', window, "<#{tk_event_sequence(context)}>")
    end
  end

  def messageBox(keys)
    tk_call 'tk_messageBox', *hash_kv(keys)
  end

  def getOpenFile(keys = nil)
    tk_call 'tk_getOpenFile', *hash_kv(keys)
  end

  def getSaveFile(keys = nil)
    tk_call 'tk_getSaveFile', *hash_kv(keys)
  end

  def chooseColor(keys = nil)
    tk_call 'tk_chooseColor', *hash_kv(keys)
  end

  def tk_call(*args)
    print args.join(" "), "\n" if $DEBUG
    args.filter {|x|ruby2tcl(x)}
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
	fail unless /^invalid command/ =~ $!
	fail err
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

  TCL_VERSION = INTERP._invoke("info", "tclversion")
  TK_VERSION  = INTERP._invoke("set", "tk_version")
  JAPANIZED_TK = (INTERP._invoke("info", "commands", "kanji") != "")

  def root
    TkRoot.new
  end

  def bell
    tk_call 'bell'
  end

  def Tk.focus(display=nil)
    if display == nil
      r = tk_call('focus')
    else
      r = tk_call('focus', '-displayof', display)
    end
    tk_tcl2ruby(r)
  end

  def Tk.focus_lastfor(win)
    tk_tcl2ruby(tk_call('focus', '-lastfor', win))
  end

  def Tk.show_kinsoku(mode='both')
    begin
      if /^8\.*/ === TK_VERSION  && JAPANIZED_TK
        tk_split_simplelist(tk_call('kinsoku', 'show', mode))
      end
    rescue
    end
  end
  def Tk.add_kinsoku(chars, mode='both')
    begin
      if /^8\.*/ === TK_VERSION  && JAPANIZED_TK
        tk_split_simplelist(tk_call('kinsoku', 'add', mode, 
                                    *(chars.split(''))))
      else
        []
      end
    rescue
      []
    end
  end
  def Tk.delete_kinsoku(chars, mode='both')
    begin
      if /^8\.*/ === TK_VERSION  && JAPANIZED_TK
        tk_split_simplelist(tk_call('kinsoku', 'delete', mode, 
                            *(chars.split(''))))
      end
    rescue
    end
  end

  def toUTF8(str,encoding)
    INTERP._toUTF8(str,encoding)
  end
  
  def fromUTF8(str,encoding)
    INTERP._fromUTF8(str,encoding)
  end

  module Scrollable
    def xscrollcommand(cmd=Proc.new)
      configure_cmd 'xscrollcommand', cmd
    end
    def yscrollcommand(cmd=Proc.new)
      configure_cmd 'yscrollcommand', cmd
    end
    def xview(*index)
      v = tk_send('xview', *index)
      list(v) if index.size == 0
    end
    def yview(*index)
      v = tk_send('yview', *index)
      list(v) if index.size == 0
    end
    def xscrollbar(bar=nil)
      if bar
	@xscrollbar = bar
	@xscrollbar.orient 'horizontal'
	self.xscrollcommand {|arg| @xscrollbar.set *arg}
	@xscrollbar.command {|arg| self.xview *arg}
      end
      @xscrollbar
    end
    def yscrollbar(bar=nil)
      if bar
	@yscrollbar = bar
	@yscrollbar.orient 'vertical'
	self.yscrollcommand {|arg| @yscrollbar.set *arg}
	@yscrollbar.command {|arg| self.yview *arg}
      end
      @yscrollbar
    end
  end

  module Wm
    include TkComm
    def aspect(*args)
      w = tk_call('wm', 'aspect', path, *args)
      list(w) if args.length == 0
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
      tk_call('wm', 'frame', path)
    end
    def geometry(*args)
      tk_call('wm', 'geometry', path, *args)
    end
    def grid(*args)
      w = tk_call('wm', 'grid', path, *args)
      list(w) if args.size == 0
    end
    def group(*args)
      w = tk_call 'wm', 'group', path, *args
      window(w) if args.size == 0
    end
    def iconbitmap(*args)
      tk_call 'wm', 'iconbitmap', path, *args
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
      list(w) if args.size == 0
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
    def protocol(name=nil, cmd=nil)
      if cmd
	tk_call('wm', 'protocol', path, name, cmd)
      elsif name
	result = tk_call('wm', 'protocol', path, name)
	(result == "")? nil : tk_tcl2ruby(result)
      else
	tk_split_simplelist(tk_call('wm', 'protocol', path))
      end
    end
    def resizable(*args)
      w = tk_call('wm', 'resizable', path, *args)
      if args.length == 0
	list(w).collect{|e| bool(e)}
      end
    end
    def sizefrom(*args)
      tk_call('wm', 'sizefrom', path, *args)
    end
    def state
      tk_call 'wm', 'state', path
    end
    def title(*args)
      tk_call 'wm', 'title', path, *args
    end
    def transient(*args)
      window(tk_call 'wm', 'transient', path, *args)
    end
    def withdraw
      tk_call 'wm', 'withdraw', path
    end
  end
end

module TkBindCore
  def bind(context, cmd=Proc.new, args=nil)
    Tk.bind(to_eval, context, cmd, args)
  end

  def bind_append(context, cmd=Proc.new, args=nil)
    Tk.bind_append(to_eval, context, cmd, args)
  end

  def bind_remove(context)
    Tk.bind_remove(to_eval, context)
  end

  def bindinfo(context=nil)
    Tk.bindinfo(to_eval, context)
  end
end

class TkBindTag
  include TkBindCore

  BTagID_TBL = {}
  Tk_BINDTAG_ID = ["btag00000"]

  def TkBindTag.id2obj(id)
    BTagID_TBL[id]? BTagID_TBL[id]: id
  end

  def initialize(*args)
    @id = Tk_BINDTAG_ID[0]
    Tk_BINDTAG_ID[0] = Tk_BINDTAG_ID[0].succ
    BTagID_TBL[@id] = self
    bind(*args) if args != []
  end

  def to_eval
    @id
  end

  def inspect
    format "#<TkBindTag: %s>", @id
  end
end

class TkBindTagAll<TkBindTag
  BindTagALL = []
  def TkBindTagAll.new(*args)
    if BindTagALL[0]
      BindTagALL[0].bind(*args) if args != []
    else
      new = super()
      BindTagALL[0] = new
    end
    BindTagALL[0]
  end

  def initialize(*args)
    @id = 'all'
    BindTagALL[0].bind(*args) if args != []
  end
end

class TkVariable
  include Tk
  extend TkCore

  TkVar_CB_TBL = {}
  Tk_VARIABLE_ID = ["v00000"]

  INTERP._invoke("proc", "rb_var", "args", "ruby [format \"TkVariable.callback %%Q!%s!\" $args]")

  def TkVariable.callback(args)
    name1,name2,op = tk_split_list(args)
    if TkVar_CB_TBL[name1]
      _get_eval_string(TkVar_CB_TBL[name1].trace_callback(name2,op))
    else
      ''
    end
  end

  def initialize(val="")
    @id = Tk_VARIABLE_ID[0]
    Tk_VARIABLE_ID[0] = Tk_VARIABLE_ID[0].succ
    if val == []
      INTERP._eval(format('global %s; set %s(0) 0; unset %s(0)', 
			  @id, @id, @id))
    elsif val.kind_of?(Array)
      a = []
      val.each_with_index{|e,i| a.push(i); a.push(array2tk_list(e))}
      s = '"' + a.join(" ").gsub(/[][$"]/, '\\\\\&') + '"'
      INTERP._eval(format('global %s; array set %s %s', @id, @id, s))
    elsif  val.kind_of?(Hash)
      s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
                   .gsub(/[][$"]/, '\\\\\&') + '"'
      INTERP._eval(format('global %s; array set %s %s', @id, @id, s))
    else
      s = '"' + _get_eval_string(val).gsub(/[][$"]/, '\\\\\&') + '"'
      INTERP._eval(format('global %s; set %s %s', @id, @id, s))
    end
  end

  def wait
    INTERP._eval("tkwait variable #{@id}")
  end

  def id
    @id
  end

  def value
    begin
      INTERP._eval(format('global %s; set %s', @id, @id))
    rescue
      if INTERP._eval(format('global %s; array exists %s', @id, @id)) != "1"
	fail
      else
	Hash[*tk_split_simplelist(INTERP._eval(format('global %s; array get %s', 
						      @id, @id)))]
      end
    end
  end

  def value=(val)
    begin
      s = '"' + _get_eval_string(val).gsub(/[][$"]/, '\\\\\&') + '"'
      INTERP._eval(format('global %s; set %s %s', @id, @id, s))
    rescue
      if INTERP._eval(format('global %s; array exists %s', @id, @id)) != "1"
	fail
      else
	if val == []
	  INTERP._eval(format('global %s; unset %s; set %s(0) 0; unset %s(0)', 
			      @id, @id, @id, @id))
	elsif val.kind_of?(Array)
	  a = []
	  val.each_with_index{|e,i| a.push(i); a.push(array2tk_list(e))}
	  s = '"' + a.join(" ").gsub(/[][$"]/, '\\\\\&') + '"'
	  INTERP._eval(format('global %s; unset %s; array set %s %s', 
			      @id, @id, @id, s))
	elsif  val.kind_of?(Hash)
	  s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
	                        .gsub(/[][$"]/, '\\\\\&') + '"'
	  INTERP._eval(format('global %s; unset %s; array set %s %s', 
			      @id, @id, @id, s))
	else
	  fail
	end
      end
    end
  end

  def [](index)
    INTERP._eval(format('global %s; set %s(%s)', 
			@id, @id, _get_eval_string(index)))
  end

  def []=(index,val)
    INTERP._eval(format('global %s; set %s(%s) %s', @id, @id, 
			_get_eval_string(index), _get_eval_string(val)))
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
    format "#<TkVariable: %s>", @id
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

  def unset(elem=nil)
    if elem
      INTERP._eval(format('global %s; unset %s(%s)', 
			  @id, @id, tk_tcl2ruby(elem)))
    else
      INTERP._eval(format('global %s; unset %s', @id, @id))
    end
  end
  alias remove unset

  def trace_callback(elem, op)
    if @trace_var.kind_of? Array
      @trace_var.each{|m,e| e.call(self,elem,op) if m.index(op)}
    end
    if elem.kind_of? String
      if @trace_elem[elem].kind_of? Array
	@trace_elem[elem].each{|m,e| e.call(self,elem,op) if m.index(op)}
      end
    end
  end

  def trace(opts, cmd)
    @trace_var = [] if @trace_var == nil
    opts = ['r','w','u'].find_all{|c| opts.index(c)}.join('')
    @trace_var.unshift([opts,cmd])
    if @trace_opts == nil
      TkVar_CB_TBL[@id] = self
      @trace_opts = opts
      Tk.tk_call('trace', 'variable', @id, @trace_opts, 'rb_var')
    else
      newopts = @trace_opts.dup
      opts.each_byte{|c| newopts += c.chr unless newopts.index(c)}
      if newopts != @trace_opts
	Tk.tk_call('trace', 'vdelete', @id, @trace_opts, 'rb_var')
	@trace_opts.replace(newopts)
	Tk.tk_call('trace', 'variable', @id, @trace_opts, 'rb_var')
      end
    end
  end

  def trace_element(elem, opts, cmd)
    @trace_elem = {} if @trace_elem == nil
    @trace_elem[elem] = [] if @trace_elem[elem] == nil
    opts = ['r','w','u'].find_all{|c| opts.index(c)}.join('')
    @trace_elem[elem].unshift([opts,cmd])
    if @trace_opts == nil
      TkVar_CB_TBL[@id] = self
      @trace_opts = opts
      Tk.tk_call('trace', 'variable', @id, @trace_opts, 'rb_var')
    else
      newopts = @trace_opts.dup
      opts.each_byte{|c| newopts += c.chr unless newopts.index(c)}
      if newopts != @trace_opts
	Tk.tk_call('trace', 'vdelete', @id, @trace_opts, 'rb_var')
	@trace_opts.replace(newopts)
	Tk.tk_call('trace', 'variable', @id, @trace_opts, 'rb_var')
      end
    end
  end

  def trace_vinfo
    return [] unless @trace_var
    @trace_var.dup
  end
  def trace_vinfo_for_element(elem)
    return [] unless @trace_elem
    return [] unless @trace_elem[elem]
    @trace_elem[elem].dup
  end

  def trace_vdelete(opts,cmd)
    return unless @trace_var.kind_of? Array
    opts = ['r','w','u'].find_all{|c| opts.index(c)}.join('')
    idx = -1
    newopts = ''
    @trace_var.each_with_index{|i,e| 
      if idx < 0 && e[0] == opts && e[1] == cmd
	idx = i
	next
      end
      e[0].each_byte{|c| newopts += c.chr unless newopts.index(c)}
    }
    if idx >= 0
      @trace_var.delete_at(idx) 
    else
      return
    end

    @trace_elem.each{|elem|
      @trace_elem[elem].each{|e|
	e[0].each_byte{|c| newopts += c.chr unless newopts.index(c)}
      }
    }

    newopts = ['r','w','u'].find_all{|c| newopts.index(c)}.join('')
    if newopts != @trace_opts
      Tk.tk_call('trace', 'vdelete', @id, @trace_opts, 'rb_var')
      @trace_opts.replace(newopts)
      if @trace_opts != ''
	Tk.tk_call('trace', 'variable', @id, @trace_opts, 'rb_var')
      end
    end
  end

  def trace_vdelete_for_element(elem,opts,cmd)
    return unless @trace_elem.kind_of? Hash
    return unless @trace_elem[elem].kind_of? Array
    opts = ['r','w','u'].find_all{|c| opts.index(c)}.join('')
    idx = -1
    @trace_elem[elem].each_with_index{|i,e| 
      if idx < 0 && e[0] == opts && e[1] == cmd
	idx = i
	next
      end
    }
    if idx >= 0
      @trace_elem[elem].delete_at(idx)
    else
      return
    end

    newopts = ''
    @trace_var.each{|e| 
      e[0].each_byte{|c| newopts += c.chr unless newopts.index(c)}
    }
    @trace_elem.each{|elem|
      @trace_elem[elem].each{|e|
	e[0].each_byte{|c| newopts += c.chr unless newopts.index(c)}
      }
    }

    newopts = ['r','w','u'].find_all{|c| newopts.index(c)}.join('')
    if newopts != @trace_opts
      Tk.tk_call('trace', 'vdelete', @id, @trace_opts, 'rb_var')
      @trace_opts.replace(newopts)
      if @trace_opts != ''
	Tk.tk_call('trace', 'variable', @id, @trace_opts, 'rb_var')
      end
    end
  end
end

class TkVarAccess<TkVariable
  def initialize(varname, val=nil)
    @id = varname
    if val
      s = '"' + _get_eval_string(val).gsub(/[][$"]/, '\\\\\&') + '"' #"
      INTERP._eval(format('global %s; set %s %s', @id, @id, s))
    end
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
    tk_call 'selection', 'handle', win.path, func, type, format
  end
  def handle(func, type=None, format=None)
    TkSelection.handle self, func, type, format
  end
  def TkSelection.own(win=None, func=None)
    window(tk_call 'selection', 'own', win, func)
  end
  def own(func=None)
    TkSelection.own self, func
  end

  module_function :clear, :get
end

module TkKinput
  include Tk
  extend Tk

  def TkKinput.start(window, style=None)
    tk_call 'kinput_start', window.path, style
  end
  def kinput_start(style=None)
    TkKinput.start(self, style)
  end

  def TkKinput.send_spot(window)
    tk_call 'kinput_send_spot', window.path
  end
  def kinput_send_spot
    TkKinput.send_spot(self)
  end

  def TkKinput.input_start(window, keys=nil)
    tk_call 'kanjiInput', 'start', window.path, *hash_kv(keys)
  end
  def kanji_input_start(keys=nil)
    TkKinput.input_start(self, keys)
  end

  def TkKinput.attribute_config(window, slot, value=None)
    if slot.kind_of? Hash
      tk_call 'kanjiInput', 'attribute', window.path, *hash_kv(slot)
    else
      tk_call 'kanjiInput', 'attribute', window.path, "-#{slot}", value
    end
  end
  def kinput_attribute_config(slot, value=None)
    TkKinput.attribute_config(self, slot, value)
  end

  def TkKinput.attribute_info(window, slot=nil)
    if slot
      conf = tk_split_list(tk_call('kanjiInput', 'attribute', 
				   window.path, "-#{slot}"))
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_list(tk_call('kanjiInput', 'attribute', 
			    window.path)).collect{|conf|
	conf[0] = conf[0][1..-1]
	conf
      }
    end
  end
  def kinput_attribute_info(slot=nil)
    TkKinput.attribute_info(self, slot)
  end

  def TkKinput.input_end(window)
    tk_call 'kanjiInput', 'end', window.path
  end
  def kanji_input_end
    TkKinput.input_end(self)
  end
end

module TkXIM
  include Tk
  extend Tk

  def TkXIM.useinputmethods(window=nil, value=nil)
    if window
      if value
        tk_call 'tk', 'useinputmethods', '-displayof', window.path, value
      else
        tk_call 'tk', 'useinputmethods', '-displayof', window.path
      end
    else
      if value
        tk_call 'tk', 'useinputmethods', value
      else
        tk_call 'tk', 'useinputmethods'
      end
    end
  end

  def TkXIM.configure(window, slot, value=None)
    begin
      if /^8\.*/ === Tk::TK_VERSION  && JAPANIZED_TK
        if slot.kind_of? Hash
          tk_call 'imconfigure', window.path, *hash_kv(slot)
        else
          tk_call 'imconfigure', window.path, "-#{slot}", value
        end
      end
    rescue
    end
  end

  def TkXIM.configinfo(window, slot=nil)
    begin
      if /^8\.*/ === Tk::TK_VERSION  && JAPANIZED_TK
        if slot
          conf = tk_split_list(tk_call('imconfigure', window.path, "-#{slot}"))
          conf[0] = conf[0][1..-1]
          conf
        else
          tk_split_list(tk_call('imconfigure', window.path)).collect{|conf|
            conf[0] = conf[0][1..-1]
            conf
          }
        end
      else
        []
      end
    rescue
      []
    end
  end

  def useinputmethods(value=nil)
    TkXIM.useinputmethods(self, value=nil)
  end

  def imconfigure(window, slot, value=None)
    TkXIM.configinfo(window, slot, value)
  end

  def imconfiginfo(slot=nil)
    TkXIM.configinfo(window, slot)
  end
end

module TkXIM
  include Tk
  extend Tk

  def TkXIM.useinputmethods(window=nil,value=nil)
    if window
      if value
        tk_call 'tk', 'useinputmethods', '-displayof', window.path, value
      else
        tk_call 'tk', 'useinputmethods', '-displayof', window.path
      end
    else
      if value
        tk_call 'tk', 'useinputmethods', value
      else
        tk_call 'tk', 'useinputmethods'
      end
    end
  end

  def useinputmethods(value=nil)
    TkXIM.useinputmethods(self,value)
  end
end

module TkWinfo
  include Tk
  extend Tk
  def TkWinfo.atom(name)
    number(tk_call 'winfo', 'atom', name)
  end
  def winfo_atom(name)
    TkWinfo.atom name
  end
  def TkWinfo.atomname(id)
    tk_call 'winfo', 'atomname', id
  end
  def winfo_atomname(id)
    TkWinfo.atomname id
  end
  def TkWinfo.cells(window)
    number(tk_call('winfo', 'cells', window.path))
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
  def TkWinfo.colormapfull(window)
     bool(tk_call('winfo', 'colormapfull', window.path))
  end
  def winfo_colormapfull
    TkWinfo.colormapfull self
  end
  def TkWinfo.containing(rootX, rootY)
    path = tk_call('winfo', 'containing', rootX, rootY)
    window(path)
  end
  def winfo_containing(x, y)
    TkWinfo.containing x, y
  end
  def TkWinfo.depth(window)
    number(tk_call('winfo', 'depth', window.path))
  end
  def winfo_depth
    TkWinfo.depth self
  end
  def TkWinfo.exist?(window)
    bool(tk_call('winfo', 'exists', window.path))
  end
  def winfo_exist?
    TkWinfo.exist? self
  end
  def TkWinfo.fpixels(window, number)
    number(tk_call('winfo', 'fpixels', window.path, number))
  end
  def winfo_fpixels(number)
    TkWinfo.fpixels self, number
  end
  def TkWinfo.geometry(window)
    tk_call('winfo', 'geometry', window.path)
  end
  def winfo_geometry
    TkWinfo.geometry self
  end
  def TkWinfo.height(window)
    number(tk_call('winfo', 'height', window.path))
  end
  def winfo_height
    TkWinfo.height self
  end
  def TkWinfo.id(window)
    tk_call('winfo', 'id', window.path)
  end
  def winfo_id
    TkWinfo.id self
  end
  def TkWinfo.interps(window=nil)
    if window
      tk_split_simplelist(tk_call('winfo', 'interps',
				  '-displayof', window.path))
    else
      tk_split_simplelist(tk_call('winfo', 'interps'))
    end
  end
  def winfo_interps
    TkWinfo.interps self
  end
  def TkWinfo.mapped?(window)
    bool(tk_call('winfo', 'ismapped', window.path))
  end
  def winfo_mapped?
    TkWinfo.mapped? self
  end
  def TkWinfo.manager(window)
    tk_call('winfo', 'manager', window.path)
  end
  def winfo_manager
    TkWinfo.manager self
  end
  def TkWinfo.appname(window)
    tk_call('winfo', 'name', window.path)
  end
  def winfo_appname
    TkWinfo.appname self
  end
  def TkWinfo.parent(window)
    window(tk_call('winfo', 'parent', window.path))
  end
  def winfo_parent
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
  def winfo_pixels(number)
    TkWinfo.pixels self, number
  end
  def TkWinfo.reqheight(window)
    number(tk_call('winfo', 'reqheight', window.path))
  end
  def winfo_reqheight
    TkWinfo.reqheight self
  end
  def TkWinfo.reqwidth(window)
    number(tk_call('winfo', 'reqwidth', window.path))
  end
  def winfo_reqwidth
    TkWinfo.reqwidth self
  end
  def TkWinfo.rgb(window, color)
    list(tk_call('winfo', 'rgb', window.path, color))
  end
  def winfo_rgb(color)
    TkWinfo.rgb self, color
  end
  def TkWinfo.rootx(window)
    number(tk_call('winfo', 'rootx', window.path))
  end
  def winfo_rootx
    TkWinfo.rootx self
  end
  def TkWinfo.rooty(window)
    number(tk_call('winfo', 'rooty', window.path))
  end
  def winfo_rooty
    TkWinfo.rooty self
  end
  def TkWinfo.screen(window)
    tk_call 'winfo', 'screen', window.path
  end
  def winfo_screen
    TkWinfo.screen self
  end
  def TkWinfo.screencells(window)
    number(tk_call('winfo', 'screencells', window.path))
  end
  def winfo_screencells
    TkWinfo.screencells self
  end
  def TkWinfo.screendepth(window)
    number(tk_call('winfo', 'screendepth', window.path))
  end
  def winfo_screendepth
    TkWinfo.screendepth self
  end
  def TkWinfo.screenheight (window)
    number(tk_call('winfo', 'screenheight', window.path))
  end
  def winfo_screenheight
    TkWinfo.screenheight self
  end
  def TkWinfo.screenmmheight(window)
    number(tk_call('winfo', 'screenmmheight', window.path))
  end
  def winfo_screenmmheight
    TkWinfo.screenmmheight self
  end
  def TkWinfo.screenmmwidth(window)
    number(tk_call('winfo', 'screenmmwidth', window.path))
  end
  def winfo_screenmmwidth
    TkWinfo.screenmmwidth self
  end
  def TkWinfo.screenvisual(window)
    tk_call 'winfo', 'screenvisual', window.path
  end
  def winfo_screenvisual
    TkWinfo.screenvisual self
  end
  def TkWinfo.screenwidth(window)
    number(tk_call('winfo', 'screenwidth', window.path))
  end
  def winfo_screenwidth
    TkWinfo.screenwidth self
  end
  def TkWinfo.server(window)
    tk_call 'winfo', 'server', window.path
  end
  def winfo_server
    TkWinfo.server self
  end
  def TkWinfo.toplevel(window)
    window(tk_call('winfo', 'toplevel', window.path))
  end
  def winfo_toplevel
    TkWinfo.toplevel self
  end
  def TkWinfo.visual(window)
    tk_call 'winfo', 'visual', window.path
  end
  def winfo_visual
    TkWinfo.visual self
  end
  def TkWinfo.visualid(window)
    tk_call 'winfo', 'visualid', window.path
  end
  def winfo_visualid
    TkWinfo.visualid self
  end
  def TkWinfo.visualsavailable(window, includeids=false)
    if includeids
      v = tk_call('winfo', 'visualsavailable', window.path, "includeids")
    else
      v = tk_call('winfo', 'visualsavailable', window.path)
    end
    list(v)
  end
  def winfo_visualsavailable(includeids=false)
    TkWinfo.visualsavailable self, includeids
  end
  def TkWinfo.vrootheight(window)
    number(tk_call('winfo', 'vrootheight', window.path))
  end
  def winfo_vrootheight
    TkWinfo.vrootheight self
  end
  def TkWinfo.vrootwidth(window)
    number(tk_call('winfo', 'vrootwidth', window.path))
  end
  def winfo_vrootwidth
    TkWinfo.vrootwidth self
  end
  def TkWinfo.vrootx(window)
    number(tk_call('winfo', 'vrootx', window.path))
  end
  def winfo_vrootx
    TkWinfo.vrootx self
  end
  def TkWinfo.vrooty(window)
    number(tk_call('winfo', 'vrooty', window.path))
  end
  def winfo_vrooty
    TkWinfo.vrooty self
  end
  def TkWinfo.width(window)
    number(tk_call('winfo', 'width', window.path))
  end
  def winfo_width
    TkWinfo.width self
  end
  def TkWinfo.x(window)
    number(tk_call('winfo', 'x', window.path))
  end
  def winfo_x
    TkWinfo.x self
  end
  def TkWinfo.y(window)
    number(tk_call('winfo', 'y', window.path))
  end
  def winfo_y
    TkWinfo.y self
  end
  def TkWinfo.viewable(window)
    bool(tk_call 'winfo', 'viewable', window.path)
  end
  def winfo_viewable
    TkWinfo.viewable self
  end
  def TkWinfo.pointerx(window)
    number(tk_call('winfo', 'pointerx', window.path))
  end
  def winfo_pointerx
    TkWinfo.pointerx self
  end
  def TkWinfo.pointery(window)
    number(tk_call('winfo', 'pointery', window.path))
  end
  def winfo_pointery
    TkWinfo.pointery self
  end
  def TkWinfo.pointerxy(window)
    list(tk_call('winfo', 'pointerxy', window.path))
  end
  def winfo_pointerxy
    TkWinfo.pointerxy self
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

module TkGrid
  include Tk
  extend Tk

  def bbox(*args)
    list(tk_call('grid', 'bbox', *args))
  end

  def configure(widget, *args)
    if args[-1].kind_of?(Hash)
      keys = args.pop
    end
    wins = [widget.epath]
    for i in args
      wins.push i.epath
    end
    tk_call "grid", 'configure', *(wins+hash_kv(keys))
  end

  def columnconfigure(master, index, args)
    tk_call "grid", 'columnconfigure', master, index, *hash_kv(args)
  end

  def rowconfigure(master, index, args)
    tk_call "grid", 'rowconfigure', master, index, *hash_kv(args)
  end

  def add(widget, *args)
    configure(widget, *args)
  end

  def forget(*args)
    tk_call 'grid', 'forget', *args
  end

  def info(slave)
    list(tk_call('grid', 'info', slave))
  end

  def location(master, x, y)
    list(tk_call('grid', 'location', master, x, y))
  end

  def propagate(master, bool=None)
    bool(tk_call('grid', 'propagate', master.epath, bool))
  end

  def remove(*args)
    tk_call 'grid', 'remove', *args
  end

  def size(master)
    tk_call 'grid', 'size', master
  end

  def slaves(args)
    list(tk_call('grid', 'slaves', *hash_kv(args)))
  end

  module_function :bbox, :forget, :propagate, :info
  module_function :remove, :size, :slaves, :location
  module_function :configure, :columnconfigure, :rowconfigure
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
  def get win, name, klass
    tk_call 'option', 'get', win ,name, klass
  end
  def readfile file, pri=None
    tk_call 'option', 'readfile', file, pri
  end
  module_function :add, :clear, :get, :readfile
end

module TkTreatFont
  def font_configinfo
    ret = TkFont.used_on(self.path)
    if ret == nil
      ret = TkFont.init_widget_font(self.path, self.path, 'configure')
    end
    ret
  end
  alias fontobj font_configinfo

  def font_configure(slot)
    if (fnt = slot.delete('font'))
      if fnt.kind_of? TkFont
	return fnt.call_font_configure(self.path, self.path,'configure',slot)
      else
	latinfont_configure(fnt) if fnt
      end
    end
    if (ltn = slot.delete('latinfont'))
      latinfont_configure(ltn) if ltn
    end
    if (ltn = slot.delete('asciifont'))
      latinfont_configure(ltn) if ltn
    end
    if (knj = slot.delete('kanjifont'))
      kanjifont_configure(knj) if knj
    end

    tk_call(self.path, 'configure', *hash_kv(slot)) if slot != {}
    self
  end

  def latinfont_configure(ltn, keys=nil)
    fobj = fontobj
    if ltn.kind_of? TkFont
      conf = {}
      ltn.latin_configinfo.each{|key,val| conf[key] = val}
      if keys
	fobj.latin_configure(conf.update(keys))
      else
	fobj.latin_configure(conf)
      end
    else
      fobj.latin_replace(ltn)
    end
  end
  alias asciifont_configure latinfont_configure

  def kanjifont_configure(knj, keys=nil)
    fobj = fontobj
    if knj.kind_of? TkFont
      conf = {}
      knj.kanji_configinfo.each{|key,val| conf[key] = val}
      if keys
	fobj.kanji_configure(conf.update(keys))
      else
	fobj.kanji_configure(cond)
      end
    else
      fobj.kanji_replace(knj)
    end
  end

  def font_copy(window, tag=nil)
    if tag
      window.tagfontobj(tag).configinfo.each{|key,value|
	fontobj.configure(key,value)
      }
      fontobj.replace(window.tagfontobj(tag).latin_font, 
		      window.tagfontobj(tag).kanji_font)
    else
      window.fontobj.configinfo.each{|key,value|
	fontobj.configure(key,value)
      }
      fontobj.replace(window.fontobj.latin_font, window.fontobj.kanji_font)
    end
  end

  def latinfont_copy(window, tag=nil)
    if tag
      fontobj.latin_replace(window.tagfontobj(tag).latin_font)
    else
      fontobj.latin_replace(window.fontobj.latin_font)
    end
  end
  alias asciifont_copy latinfont_copy

  def kanjifont_copy(window, tag=nil)
    if tag
      fontobj.kanji_replace(window.tagfontobj(tag).kanji_font)
    else
      fontobj.kanji_replace(window.fontobj.kanji_font)
    end
  end
end

class TkObject<TkKernel
  include Tk
  include TkTreatFont
  include TkBindCore

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
    name = id.id2name
    case args.length
    when 1
      configure name, args[0]
    when 0
      begin
	cget name
      rescue
	fail NameError, "undefined local variable or method `#{name}' for #{self.to_s}", error_at
      end
    else
      fail NameError, "undefined method `#{name}' for #{self.to_s}", error_at
    end
  end

  def [](id)
    cget id
  end

  def []=(id, val)
    configure id, val
  end

  def cget(slot)
    tk_tcl2ruby tk_call path, 'cget', "-#{slot}"
  end

  def configure(slot, value=None)
    if slot.kind_of? Hash
      if (slot['font'] || slot['kanjifont'] ||
	  slot['latinfont'] || slot['asciifont'] )
	font_configure(slot.dup)
      else
	tk_call path, 'configure', *hash_kv(slot)
      end

    else
      if (slot == 'font' || slot == 'kanjifont' ||
	  slot == 'latinfont' || slot == 'asciifont')
	if value == None
	  fontobj
	else
	  font_configure({slot=>value})
	end
      else
	tk_call path, 'configure', "-#{slot}", value
      end
    end
  end

  def configure_cmd(slot, value)
    configure slot, install_cmd(value)
  end

  def configinfo(slot = nil)
    if slot == 'font' || slot == 'kanjifont'
      fontobj
    else
      if slot
	conf = tk_split_list(tk_send('configure', "-#{slot}") )
	conf[0] = conf[0][1..-1]
	conf
      else
	ret = tk_split_list(tk_send('configure') ).collect{|conf|
	  conf[0] = conf[0][1..-1]
	  conf
	}
	if ret.assoc('font')
	  ret.delete_if{|item| item[0] == 'font' || item[0] == 'kanjifont'}
	  ret.push(['font', fontobj])
	else
	  ret
	end
      end
    end
  end

  def event_generate(context, keys=nil)
    if keys
      tk_call('event', 'generate', path, 
	      "<#{tk_event_sequence(context)}>", *hash_kv(keys))
    else
      tk_call('event', 'generate', path, "<#{tk_event_sequence(context)}>")
    end
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
  extend TkBindCore

  def initialize(parent=nil, keys=nil)
    install_win(if parent then parent.path end)
    create_self
    if keys
      # tk_call @path, 'configure', *hash_kv(keys)
      configure(keys)
    end
  end

  def create_self
  end
  private :create_self

  def pack(keys = nil)
    tk_call 'pack', epath, *hash_kv(keys)
    self
  end

  def unpack
    tk_call 'pack', 'forget', epath
    self
  end

  def grid(keys = nil)
    tk_call 'grid', epath, *hash_kv(keys)
    self
  end

  def ungrid
    tk_call 'grid', 'forget', epath
    self
  end

  def place(keys = nil)
    tk_call 'place', epath, *hash_kv(keys)
    self
  end

  def unplace
    tk_call 'place', 'forget', epath
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

  def focus(force=false)
    if force
      tk_call 'focus', '-force', path
    else
      tk_call 'focus', path
    end
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
	val = tk_call('grab', args[0], path)
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
    tk_call 'lower', epath, below
    self
  end
  def raise(above=None)
    tk_call 'raise', epath, above
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
    tk_call 'destroy', epath
    if @cmdtbl
      for id in @cmdtbl
	uninstall_cmd id
      end
    end
    uninstall_win
  end

  def wait_visibility
    tk_call 'tkwait', 'visibility', path
  end
  alias wait wait_visibility

  def wait_destroy
    tk_call 'tkwait', 'window', epath
  end

  def bindtags(taglist=nil)
    if taglist
      fail unless taglist.kind_of? Array
      tk_call('bindtags', path, taglist)
    else
      list(tk_call('bindtags', path)).collect{|tag|
	if tag.kind_of?(String) 
	  if cls = WidgetClassNames[tag]
	    cls
	  elsif btag = TkBindTag.id2obj(tag)
	    btag
	  else
	    tag
	  end
	else
	  tag
	end
      }
    end
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

  WidgetClassName = 'Tk'.freeze
  WidgetClassNames[WidgetClassName] = self
  def self.to_eval
    WidgetClassName
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

  WidgetClassName = 'Toplevel'.freeze
  WidgetClassNames[WidgetClassName] = self
  def self.to_eval
    WidgetClassName
  end

  def initialize(parent=nil, screen=nil, classname=nil, keys=nil)
    if screen.kind_of? Hash
      keys = screen.dup
    else
      @screen = screen
    end
    @classname = classname
    if keys.kind_of? Hash
      keys = keys.dup
      @classname = keys.delete('classname') if keys.key?('classname')
      @colormap  = keys.delete('colormap')  if keys.key?('colormap')
      @container = keys.delete('container') if keys.key?('container')
      @screen    = keys.delete('screen')    if keys.key?('screen')
      @use       = keys.delete('use')       if keys.key?('use')
      @visual    = keys.delete('visual')    if keys.key?('visual')
    end
    super(parent, keys)
  end

  def create_self
    s = []
    s << "-class"     << @classname if @classname
    s << "-colormap"  << @colormap  if @colormap
    s << "-container" << @container if @container
    s << "-screen"    << @screen    if @screen 
    s << "-use"       << @use       if @use
    s << "-visual"    << @visual    if @visual
    tk_call 'toplevel', @path, *s
  end

  def specific_class
    @classname
  end
end

class TkFrame<TkWindow
  WidgetClassName = 'Frame'.freeze
  WidgetClassNames[WidgetClassName] = self
  def self.to_eval
    WidgetClassName
  end

  def initialize(parent=nil, keys=nil)
    if keys.kind_of? Hash
      keys = keys.dup
      @classname = keys.delete('classname') if keys.key?('classname')
      @colormap  = keys.delete('colormap')  if keys.key?('colormap')
      @container = keys.delete('container') if keys.key?('container')
      @visual    = keys.delete('visual')    if keys.key?('visual')
    end
    super(parent, keys)
  end

  def create_self
    s = []
    s << "-class"     << @classname if @classname
    s << "-colormap"  << @colormap  if @colormap
    s << "-container" << @container if @container
    s << "-visual"    << @visual    if @visual
    tk_call 'frame', @path, *s
  end
end

class TkLabel<TkWindow
  WidgetClassName = 'Label'.freeze
  WidgetClassNames[WidgetClassName] = self
  def self.to_eval
    WidgetClassName
  end
  def create_self
    tk_call 'label', @path
  end
  def textvariable(v)
    configure 'textvariable', tk_trace_variable(v)
  end
end

class TkButton<TkLabel
  WidgetClassNames['Button'] = self
  def TkButton.to_eval
    'Button'
  end
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
  WidgetClassNames['Radiobutton'] = self
  def TkRadioButton.to_eval
    'Radiobutton'
  end
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
  WidgetClassNames['Checkbutton'] = self
  def TkCheckButton.to_eval
    'Checkbutton'
  end
  def create_self
    tk_call 'checkbutton', @path
  end
  def toggle
    tk_send 'toggle'
  end
end

class TkMessage<TkLabel
  WidgetClassNames['Message'] = self
  def TkMessage.to_eval
    'Message'
  end
  def create_self
    tk_call 'message', @path
  end
end

class TkScale<TkWindow
  WidgetClassName = 'Scale'.freeze
  WidgetClassNames[WidgetClassName] = self
  def self.to_eval
    WidgetClassName
  end

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
  WidgetClassName = 'Scrollbar'.freeze
  WidgetClassNames[WidgetClassName] = self
  def self.to_eval
    WidgetClassName
  end

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
    ary1 = tk_send('get').split
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
  def create_self
    fail TypeError, "TkTextWin is abstract class"
  end

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
  include Scrollable

  WidgetClassNames['Listbox'] = self
  def TkListbox.to_eval
    'Listbox'
  end
  def create_self
    tk_call 'listbox', path
  end

  def activate(y)
    tk_send 'activate', y
  end
  def curselection
    list(tk_send('curselection'))
  end
  def get(*index)
    v = tk_send('get', *index)
    if index.size == 1
      v
    else
      tk_split_simplelist(v)
    end
  end
  def nearest(y)
    tk_send('nearest', y).to_i
  end
  def size
    tk_send('size').to_i
  end
  def selection_anchor(index)
    tk_send 'selection', 'anchor', index
  end
  def selection_clear(first, last=None)
    tk_send 'selection', 'clear', first, last
  end
  def selection_includes(index)
    bool(tk_send('selection', 'includes', index))
  end
  def selection_set(first, last=None)
    tk_send 'selection', 'set', first, last
  end

  def itemcget(index, key)
    tk_tcl2ruby tk_send 'itemcget', index, "-#{key}"
  end
  def itemconfigure(index, key, val=None)
    if key.kind_of? Hash
      if (key['font'] || key['kanjifont'] ||
	  key['latinfont'] || key['asciifont'])
	tagfont_configure(index, key.dup)
      else
	tk_send 'itemconfigure', index, *hash_kv(key)
      end

    else
      if (key == 'font' || key == 'kanjifont' ||
	  key == 'latinfont' || key == 'asciifont' )
	tagfont_configure({key=>val})
      else
	tk_call 'itemconfigure', index, "-#{key}", val
      end
    end
  end

  def itemconfiginfo(index, key=nil)
    if key
      conf = tk_split_list(tk_send('itemconfigure',index,"-#{key}"))
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_list(tk_send('itemconfigure', index)).collect{|conf|
	conf[0] = conf[0][1..-1]
	conf
      }
    end
  end
end

module TkTreatMenuEntryFont
  def tagfont_configinfo(index)
    pathname = self.path + ';' + index
    ret = TkFont.used_on(pathname)
    if ret == nil
      ret = TkFont.init_widget_font(pathname, 
				    self.path, 'entryconfigure', index)
    end
    ret
  end
  alias tagfontobj tagfont_configinfo

  def tagfont_configure(index, slot)
    pathname = self.path + ';' + index
    if (fnt = slot.delete('font'))
      if fnt.kind_of? TkFont
	return fnt.call_font_configure(pathname, 
				       self.path,'entryconfigure',index,slot)
      else
	latintagfont_configure(index, fnt) if fnt
      end
    end
    if (ltn = slot.delete('latinfont'))
      latintagfont_configure(index, ltn) if ltn
    end
    if (ltn = slot.delete('asciifont'))
      latintagfont_configure(index, ltn) if ltn
    end
    if (knj = slot.delete('kanjifont'))
      kanjitagfont_configure(index, knj) if knj
    end

    tk_call(self.path, 'entryconfigure', index, *hash_kv(slot)) if slot != {}
    self
  end

  def latintagfont_configure(index, ltn, keys=nil)
    fobj = tagfontobj(index)
    if ltn.kind_of? TkFont
      conf = {}
      ltn.latin_configinfo.each{|key,val| conf[key] = val if val != []}
      if conf == {}
	fobj.latin_replace(ltn)
	fobj.latin_configure(keys) if keys
      elsif keys
	fobj.latin_configure(conf.update(keys))
      else
	fobj.latin_configure(conf)
      end
    else
      fobj.latin_replace(ltn)
    end
  end
  alias asciitagfont_configure latintagfont_configure

  def kanjitagfont_configure(index, knj, keys=nil)
    fobj = tagfontobj(index)
    if knj.kind_of? TkFont
      conf = {}
      knj.kanji_configinfo.each{|key,val| conf[key] = val if val != []}
      if conf == {}
	fobj.kanji_replace(knj)
	fobj.kanji_configure(keys) if keys
      elsif keys
	fobj.kanji_configure(conf.update(keys))
      else
	fobj.kanji_configure(conf)
      end
    else
      fobj.kanji_replace(knj)
    end
  end

  def tagfont_copy(index, window, wintag=nil)
    if wintag
      window.tagfontobj(wintag).configinfo.each{|key,value|
	tagfontobj(index).configure(key,value)
      }
      tagfontobj(index).replace(window.tagfontobj(wintag).latin_font, 
			      window.tagfontobj(wintag).kanji_font)
    else
      window.tagfont(wintag).configinfo.each{|key,value|
	tagfontobj(index).configure(key,value)
      }
      tagfontobj(index).replace(window.fontobj.latin_font, 
			      window.fontobj.kanji_font)
    end
  end

  def latintagfont_copy(index, window, wintag=nil)
    if wintag
      tagfontobj(index).latin_replace(window.tagfontobj(wintag).latin_font)
    else
      tagfontobj(index).latin_replace(window.fontobj.latin_font)
    end
  end
  alias asciitagfont_copy latintagfont_copy

  def kanjitagfont_copy(index, window, wintag=nil)
    if wintag
      tagfontobj(index).kanji_replace(window.tagfontobj(wintag).kanji_font)
    else
      tagfontobj(index).kanji_replace(window.fontobj.kanji_font)
    end
  end
end

class TkMenu<TkWindow
  include TkTreatMenuEntryFont

  WidgetClassName = 'Menu'.freeze
  WidgetClassNames[WidgetClassName] = self
  def self.to_eval
    WidgetClassName
  end
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
  def invoke(index)
    tk_send 'invoke', index
  end
  def insert(index, type, keys=nil)
    tk_send 'add', index, type, *hash_kv(keys)
  end
  def delete(index, last=None)
    tk_send 'delete', index, last
  end
  def popup(x, y, index=nil)
    tk_call 'tk_popup', path, x, y, index
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
  def entrycget(index, key)
    tk_tcl2ruby tk_send 'entrycget', index, "-#{key}"
  end
  def entryconfigure(index, key, val=None)
    if key.kind_of? Hash
      if (key['font'] || key['kanjifont'] ||
	  key['latinfont'] || key['asciifont'])
	tagfont_configure(index, key.dup)
      else
	tk_send 'entryconfigure', index, *hash_kv(key)
      end

    else
      if (key == 'font' || key == 'kanjifont' ||
	  key == 'latinfont' || key == 'asciifont' )
	tagfont_configure({key=>val})
      else
	tk_call 'entryconfigure', index, "-#{key}", val
      end
    end
  end

  def entryconfiginfo(index, key=nil)
    if key
      conf = tk_split_list(tk_send('entryconfigure',index,"-#{key}"))
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_list(tk_send('entryconfigure', index)).collect{|conf|
	conf[0] = conf[0][1..-1]
	conf
      }
    end
  end
end

module TkSystemMenu
  def initialize(parent, keys=nil)
    fail unless parent.kind_of? TkMenu
    @path = format("%s.%s", parent.path, self.type::SYSMENU_NAME)
    TkComm::Tk_WINDOWS[@path] = self
    create_self
    configure(keys) if keys
  end
end

class TkSysMenu_Help<TkMenu
  # for all platform
  include TkSystemMenu
  SYSMENU_NAME = 'help'
end

class TkSysMenu_System<TkMenu
  # for Windows
  include TkSystemMenu
  SYSMENU_NAME = 'system'
end

class TkSysMenu_Apple<TkMenu
  # for Machintosh
  include TkSystemMenu
  SYSMENU_NAME = 'apple'
end

class TkMenubutton<TkLabel
  WidgetClassNames['Menubutton'] = self
  def TkMenubutton.to_eval
    'Menubutton'
  end
  def create_self
    tk_call 'menubutton', path
  end
end

class TkOptionMenubutton<TkMenubutton
  class OptionMenu<TkMenu
    def initialize(parent)
      @path = parent.path + '.menu'
      TkComm::Tk_WINDOWS[@path] = self
    end
  end

  def initialize(parent=nil, var=TkVariable.new, firstval=nil, *vals)
    fail unless var.kind_of? TkVariable
    @variable = var
    firstval = @variable.value unless firstval
    @variable.value = firstval
    install_win(if parent then parent.path end)
    @menu = OptionMenu.new(self)
    tk_call 'tk_optionMenu', @path, @variable.id, firstval, *vals
  end

  def value
    @variable.value
  end

  def activate(index)
    @menu.activate(index)
  end
  def add(value)
    @menu.add('radiobutton', 'variable'=>@variable, 
	      'label'=>value, 'value'=>value)
  end
  def index(index)
    @menu.index(index)
  end
  def invoke(index)
    @menu.invoke(index)
  end
  def insert(index, value)
    @menu.add(index, 'radiobutton', 'variable'=>@variable, 
	      'label'=>value, 'value'=>value)
  end
  def delete(index, last=None)
    @menu.delete(index, last)
  end
  def yposition(index)
    @menu.yposition(index)
  end
  def menucget(index, key)
    @menu.cget(index, key)
  end
  def menuconfigure(index, key, val=None)
    @menu.configure(index, key, val)
  end
  def menuconfiginfo(index, key=nil)
    @menu.configinfo(index, key)
  end
  def entrycget(index, key)
    @menu.entrycget(index, key)
  end
  def entryconfigure(index, key, val=None)
    @menu.entryconfigure(index, key, val)
  end
  def entryconfiginfo(index, key=nil)
    @menu.entryconfiginfo(index, key)
  end
end

module TkComposite
  include Tk
  extend Tk

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

module TkClipboard
  include Tk
  extend Tk

  def clear
    tk_call 'clipboard', 'clear'
  end
  def get
    begin
      tk_call 'selection', 'get', '-selection', 'CLIPBOARD'
    rescue
      ''
    end
  end
  def set(data)
    clear
    append(data)
  end
  def append(data)
    tk_call 'clipboard', 'append', data
  end

  module_function :clear, :set, :get, :append
end

autoload :TkCanvas, 'tkcanvas'
autoload :TkImage, 'tkcanvas'
autoload :TkBitmapImage, 'tkcanvas'
autoload :TkPhotoImage, 'tkcanvas'
autoload :TkEntry, 'tkentry'
autoload :TkText, 'tktext'
autoload :TkDialog, 'tkdialog'
autoload :TkMenubar, 'tkmenubar'
autoload :TkAfter, 'tkafter'
autoload :TkPalette, 'tkpalette'
autoload :TkFont, 'tkfont'
autoload :TkVirtualEvent, 'tkvirtevent'
