#
#		tk.rb - Tk interface module using tcltklib
#			$Date$
#			by Yukihiro Matsumoto <matz@netlab.jp>

# use Shigehiro's tcltklib
require "tcltklib"
require "tkutil"

module TkComm
  WidgetClassNames = {}.taint

  None = Object.new
  def None.to_s
    'None'
  end
  None.freeze

  #Tk_CMDTBL = {}
  #Tk_WINDOWS = {}
  Tk_IDs = ["00000".taint, "00000".taint].freeze  # [0]-cmdid, [1]-winid

  # for backward compatibility
  Tk_CMDTBL = Object.new
  def Tk_CMDTBL.method_missing(id, *args)
    TkCore::INTERP.tk_cmd_tbl.send(id, *args)
  end
  Tk_CMDTBL.freeze
  Tk_WINDOWS = Object.new
  def Tk_WINDOWS.method_missing(id, *args)
    TkCore::INTERP.tk_windows.send(id, *args)
  end
  Tk_WINDOWS.freeze

  self.instance_eval{
    @cmdtbl = [].taint
  }

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
      #tk_class = TkCore::INTERP._invoke('winfo', 'class', path)
      tk_class = Tk.ip_invoke('winfo', 'class', path)
    rescue
      return path
    end

    if ruby_class = WidgetClassNames[tk_class]
      ruby_class_name = ruby_class.name
      # gen_class_name = ruby_class_name + 'GeneratedOnTk'
      gen_class_name = ruby_class_name
      classname_def = ''
    elsif Object.const_defined?('Tk' + tk_class)
      ruby_class_name = 'Tk' + tk_class
      # gen_class_name = ruby_class_name + 'GeneratedOnTk'
      gen_class_name = ruby_class_name
      classname_def = ''
    else
      ruby_class_name = 'TkWindow'
      # gen_class_name = ruby_class_name + tk_class + 'GeneratedOnTk'
      gen_class_name = 'TkWidget_' + tk_class
      classname_def = "WidgetClassName = '#{tk_class}'.freeze"
    end
    unless Object.const_defined? gen_class_name
      Object.class_eval "class #{gen_class_name}<#{ruby_class_name}
                           #{classname_def}
                         end"
    end
    Object.class_eval "#{gen_class_name}.new('widgetname'=>'#{path}', 
                                             'without_creating'=>true)"
  end
  private :_genobj_for_tkwidget
  module_function :_genobj_for_tkwidget

  def tk_tcl2ruby(val)
    if val =~ /^rb_out (c\d+)/
      #return Tk_CMDTBL[$1]
      return TkCore::INTERP.tk_cmd_tbl[$1]
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
      #Tk_WINDOWS[val] ? Tk_WINDOWS[val] : _genobj_for_tkwidget(val)
      TkCore::INTERP.tk_windows[val]? 
           TkCore::INTERP.tk_windows[val] : _genobj_for_tkwidget(val)
    when /^i\d+$/
      TkImage::Tk_IMGTBL[val]? TkImage::Tk_IMGTBL[val] : val
    when / /
      val.split.collect{|elt|
	tk_tcl2ruby(elt)
      }
    when /^-?\d+\.?\d*(e[-+]?\d+)?$/
      val.to_f
    else
      val
    end
  end

  def tk_split_list(str)
    return [] if str == ""
    idx = str.index('{')
    while idx and idx > 0 and str[idx-1] == ?\\
      idx = str.index('{', idx+1)
    end
    unless idx
      list = tk_tcl2ruby(str)
      unless Array === list
        list = [list]
      end
      return list
    end

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
    if str.size == i + 1
      return tk_split_list(str[0, i])
    end
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
    while idx and idx > 0 and str[idx-1] == ?\\
      idx = str.index('{', idx+1)
    end
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

  def _symbolkey2str(keys)
    h = {}
    keys.each{|key,value| h[key.to_s] = value}
    h
  end
  private :_symbolkey2str

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
  module_function :hash_kv

  def array2tk_list(ary)
    ary.collect{|e|
      if e.kind_of? Array
	"{#{array2tk_list(e)}}"
      elsif e.kind_of? Hash
	"{#{e.to_a.collect{|ee| array2tk_list(ee)}.join(' ')}}"
      else
	s = _get_eval_string(e)
	(s.index(/\s/) || s.size == 0)? "{#{s}}": s
      end
    }.join(" ")
  end
  private :array2tk_list
  module_function :array2tk_list

  def bool(val)
    case val
    when "1", 1, 'yes', 'true'
      true
    else
      false
    end
  end
  def number(val)
    case val
    when /^-?\d+$/
      val.to_i
    when /^-?\d+\.?\d*(e[-+]?\d+)?$/
      val.to_f
    else
      fail(ArgumentError, 
	   Kernel.format('invalid value for Number:"%s"', val.to_s))
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
    tk_split_list(val)
  end
  def simplelist(val)
    tk_split_simplelist(val)
  end
  def window(val)
    if val =~ /^\./
      #Tk_WINDOWS[val]? Tk_WINDOWS[val] : _genobj_for_tkwidget(val)
      TkCore::INTERP.tk_windows[val]? 
           TkCore::INTERP.tk_windows[val] : _genobj_for_tkwidget(val)
    else
      nil
    end
  end
  def procedure(val)
    if val =~ /^rb_out (c\d+)/
      #Tk_CMDTBL[$1]
      #TkCore::INTERP.tk_cmd_tbl[$1]
      TkCore::INTERP.tk_cmd_tbl[$1].cmd
    else
      #nil
      val
    end
  end
  private :bool, :number, :string, :list, :simplelist, :window, :procedure
  module_function :bool, :number, :string, :list, :simplelist
  module_function :window, :procedure

  def _get_eval_string(str)
    return nil if str == None
    if str.kind_of?(String)
      # do nothing
    elsif str.kind_of?(Symbol)
      str = str.id2name
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
      str = str.to_s() || ''
      unless str.kind_of? String
	fail RuntimeError, "fail to convert the object to a string" 
      end
      str
    end
    return str
  end
  private :_get_eval_string
  module_function :_get_eval_string

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

  def _curr_cmd_id
    #id = format("c%.4d", Tk_IDs[0])
    id = "c" + TkComm::Tk_IDs[0]
  end
  def _next_cmd_id
    id = _curr_cmd_id
    #Tk_IDs[0] += 1
    TkComm::Tk_IDs[0].succ!
    id
  end
  private :_curr_cmd_id, :_next_cmd_id
  module_function :_curr_cmd_id, :_next_cmd_id

  def install_cmd(cmd)
    return '' if cmd == ''
    id = _next_cmd_id
    #Tk_CMDTBL[id] = cmd
    TkCore::INTERP.tk_cmd_tbl[id] = TkCore::INTERP.get_cb_entry(cmd)
    @cmdtbl = [] unless defined? @cmdtbl
    @cmdtbl.taint unless @cmdtbl.tainted?
    @cmdtbl.push id
    return Kernel.format("rb_out %s", id);
  end
  def uninstall_cmd(id)
    id = $1 if /rb_out (c\d+)/ =~ id
    #Tk_CMDTBL.delete(id)
    TkCore::INTERP.tk_cmd_tbl.delete(id)
  end
  private :install_cmd, :uninstall_cmd
  module_function :install_cmd

  def install_win(ppath,name=nil)
    if !name or name == ''
      #name = format("w%.4d", Tk_IDs[1])
      #Tk_IDs[1] += 1
      name = "w" + Tk_IDs[1]
      Tk_IDs[1].succ!
    end
    if name[0] == ?.
      @path = name.dup
    elsif !ppath or ppath == "."
      @path = Kernel.format(".%s", name);
    else
      @path = Kernel.format("%s.%s", ppath, name)
    end
    #Tk_WINDOWS[@path] = self
    TkCore::INTERP.tk_windows[@path] = self
  end

  def uninstall_win()
    #Tk_WINDOWS.delete(@path)
    TkCore::INTERP.tk_windows.delete(@path)
  end
  private :install_win, :uninstall_win

  class Event
    module TypeNum
      KeyPress         =  2
      KeyRelease       =  3
      ButtonPress      =  4
      ButtonRelease    =  5
      MotionNotify     =  6
      EnterNotify      =  7
      LeaveNotify      =  8
      FocusIn          =  9
      FocusOut         = 10
      KeymapNotify     = 11
      Expose           = 12
      GraphicsExpose   = 13
      NoExpose         = 14
      VisibilityNotify = 15
      CreateNotify     = 16
      DestroyNotify    = 17
      UnmapNotify      = 18
      MapNotify	       = 19
      MapRequest       = 20
      ReparentNotify   = 21
      ConfigureNotify  = 22
      ConfigureRequest = 23
      GravityNotify    = 24
      ResizeRequest    = 25
      CirculateNotify  = 26
      CirculateRequest = 27
      PropertyNotify   = 28
      SelectionClear   = 29
      SelectionRequest = 30
      SelectionNotify  = 31
      ColormapNotify   = 32
      ClientMessage    = 33
      MappingNotify    = 34
    end

    EV_KEY  = '#abcdfhikmopstwxyABDEKNRSTWXY'
    EV_TYPE = 'nsnnsbnsnsbsxnnnnsnnbsnssnwnn'

    def self.scan_args(arg_str, arg_val)
      arg_cnv = []
      arg_str.strip.split(/\s+/).each_with_index{|kwd,idx|
	if kwd =~ /^%(.)$/
	  if num = EV_KEY.index($1)
	    case EV_TYPE[num]
	    when ?n
	      begin
		val = TkComm::number(arg_val[idx])
	      rescue ArgumentError
		# ignore --> no convert
		val = TkComm::string(arg_val[idx])
	      end
	      arg_cnv << val
	    when ?s
	      arg_cnv << TkComm::string(arg_val[idx])
	    when ?b
	      arg_cnv << TkComm::bool(arg_val[idx])
	    when ?w
	      arg_cnv << TkComm::window(arg_val[idx])
	    when ?x
	      begin
		arg_cnv << TkComm::number(arg_val[idx])
	      rescue ArgumentError
		arg_cnv << arg_val[idx]
	      end
	    else
	      arg_cnv << arg_val[idx]
	    end
	  else
	    arg_cnv << arg_val[idx]
	  end
	else
	  arg_cnv << arg_val[idx]
	end
      }
      arg_cnv
    end

    def initialize(seq,a,b,c,d,f,h,i,k,m,o,p,s,t,w,x,y,
	           aa,bb,dd,ee,kk,nn,rr,ss,tt,ww,xx,yy)
      @serial = seq
      @above = a
      @num = b
      @count = c
      @detail = d
      @focus = f
      @height = h
      @win_hex = i
      @keycode = k
      @mode = m
      @override = o
      @place = p
      @state = s
      @time = t
      @width = w
      @x = x
      @y = y
      @char = aa
      @borderwidth = bb
      @wheel_delta = dd
      @send_event = ee
      @keysym = kk
      @keysym_num = nn
      @rootwin_id = rr
      @subwindow = ss
      @type = tt
      @widget = ww
      @x_root = xx
      @y_root = yy
    end
    attr :serial
    attr :above
    attr :num
    attr :count
    attr :detail
    attr :focus
    attr :height
    attr :win_hex
    attr :keycode
    attr :mode
    attr :override
    attr :place
    attr :state
    attr :time
    attr :width
    attr :x
    attr :y
    attr :char
    attr :borderwidth
    attr :wheel_delta
    attr :send_event
    attr :keysym
    attr :keysym_num
    attr :rootwin_id
    attr :subwindow
    attr :type
    attr :widget
    attr :x_root
    attr :y_root
  end

  def install_bind(cmd, args=nil)
    if args
      id = install_cmd(proc{|*arg|
	TkUtil.eval_cmd(cmd, *Event.scan_args(args, arg))
      })
      id + " " + args
    else
      args = ' %# %a %b %c %d %f %h %i %k %m %o %p %s %t %w %x %y' + 
             ' %A %B %D %E %K %N %R %S %T %W %X %Y'
      id = install_cmd(proc{|*arg|
	TkUtil.eval_cmd(cmd, Event.new(*Event.scan_args(args, arg)))
      })
      id + args
    end
  end

  def tk_event_sequence(context)
    if context.kind_of? TkVirtualEvent
      context = context.path
    end
    if context.kind_of? Array
      context = context.collect{|ev|
	if ev.kind_of? TkVirtualEvent
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
	  #[Tk_CMDTBL[$1], $2]
	  [TkCore::INTERP.tk_cmd_tbl[$1], $2]
	else
	  cmdline
	end
      }
    else
      tk_split_simplelist(tk_call(*what)).collect!{|seq|
	l = seq.scan(/<*[^<>]+>*/).collect!{|subseq|
	  case (subseq)
	  when /^<<[^<>]+>>$/
	    TkVirtualEvent.getobj(subseq[1..-2])
	  when /^<[^<>]+>$/
	    subseq[1..-2]
	  else
	    subseq.split('')
	  end
	}.flatten
	(l.size == 1) ? l[0] : l
      }
    end
  end
  private :install_bind, :tk_event_sequence, 
          :_bind_core, :_bind, :_bind_append, :_bind_remove, :_bindinfo

  def bind(tagOrClass, context, cmd=Proc.new, args=nil)
    _bind(["bind", tagOrClass], context, cmd, args)
    tagOrClass
  end

  def bind_append(tagOrClass, context, cmd=Proc.new, args=nil)
    _bind_append(["bind", tagOrClass], context, cmd, args)
    tagOrClass
  end

  def bind_remove(tagOrClass, context)
    _bind_remove(['bind', tagOrClass], context)
    tagOrClass
  end

  def bindinfo(tagOrClass, context=nil)
    _bindinfo(['bind', tagOrClass], context)
  end

  def bind_all(context, cmd=Proc.new, args=nil)
    _bind(['bind', 'all'], context, cmd, args)
    TkBindTag::ALL
  end

  def bind_append_all(context, cmd=Proc.new, args=nil)
    _bind_append(['bind', 'all'], context, cmd, args)
    TkBindTag::ALL
  end

  def bind_remove_all(context)
    _bind_remove(['bind', 'all'], context)
    TkBindTag::ALL
  end

  def bindinfo_all(context=nil)
    _bindinfo(['bind', 'all'], context)
  end

  def pack(*args)
    TkPack.configure(*args)
  end

  def grid(*args)
    TkGrid.configure(*args)
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

  unless self.const_defined? :INTERP
    if self.const_defined? :IP_NAME
      name = IP_NAME.to_s
    else
      #name = nil
      name = $0
    end
    if self.const_defined? :IP_OPTS
      if IP_OPTS.kind_of?(Hash)
	opts = hash_kv(IP_OPTS).join(' ')
      else
	opts = IP_OPTS.to_s
      end
    else
      opts = ''
    end

    INTERP = TclTkIp.new(name, opts)

    def INTERP.__getip
      self
    end

    INTERP.instance_eval{
      @tk_cmd_tbl = {}.taint
      @tk_windows = {}.taint

      @tk_table_list = [].taint

      @init_ip_env  = [].taint  # table of Procs
      @add_tk_procs = [].taint  # table of [name, args, body]

      @cb_entry_class = Class.new{|c|
	def initialize(ip, cmd)
	  @ip = ip
	  @cmd = cmd
	end
	attr_reader :ip, :cmd
	def call(*args)
	  @ip.cb_eval(@cmd, *args)
	end
      }
    }

    def INTERP.tk_cmd_tbl
      @tk_cmd_tbl
    end
    def INTERP.tk_windows
      @tk_windows
    end

    def INTERP.tk_object_table(id)
      @tk_table_list[id]
    end
    def INTERP.create_table
      id = @tk_table_list.size
      (tbl = {}).tainted? || tbl.taint
      @tk_table_list << tbl
      obj = Object.new
      obj.instance_eval <<-EOD
        def self.method_missing(m, *args)
	  TkCore::INTERP.tk_object_table(#{id}).send(m, *args)
        end
      EOD
      return obj
    end

    def INTERP.get_cb_entry(cmd)
      @cb_entry_class.new(__getip, cmd).freeze
    end
    def INTERP.cb_eval(cmd, *args)
      TkComm._get_eval_string(TkUtil.eval_cmd(cmd, *args))
    end

    def INTERP.init_ip_env(script = Proc.new)
      @init_ip_env << script
      script.call(self)
    end
    def INTERP.add_tk_procs(name, args = nil, body = nil)
      @add_tk_procs << [name, args, body]
      self._invoke('proc', name, args, body) if args && body
    end
    def INTERP.init_ip_internal
      ip = self
      @init_ip_env.each{|script| script.call(ip)}
      @add_tk_procs.each{|name,args,body| ip._invoke('proc',name,args,body)}
    end
  end

  INTERP.add_tk_procs('rb_out', 'args', <<-'EOL')
    regsub -all {!} $args {\\!} args
    regsub -all "{" $args "\\{" args
    if {[set st [catch {ruby [format "TkCore.callback %%Q!%s!" $args]} ret]] != 0} {
	return -code $st $ret
    } {
	return $ret
    }
  EOL

  EventFlag = TclTkLib::EventFlag

  def callback_break
    fail TkCallbackBreak, "Tk callback returns 'break' status"
  end

  def callback_continue
    fail TkCallbackContinue, "Tk callback returns 'continue' status"
  end

  def TkCore.callback(arg)
    # arg = tk_split_list(arg)
    arg = tk_split_simplelist(arg)
    #_get_eval_string(TkUtil.eval_cmd(Tk_CMDTBL[arg.shift], *arg))
    #_get_eval_string(TkUtil.eval_cmd(TkCore::INTERP.tk_cmd_tbl[arg.shift], 
    #  			     *arg))
    cb_obj = TkCore::INTERP.tk_cmd_tbl[arg.shift]
    unless $DEBUG
      cb_obj.call(*arg)
    else
      begin
	raise 'check backtrace'
      rescue
	# ignore backtrace before 'callback'
	pos = -($!.backtrace.size)
      end
      begin
	cb_obj.call(*arg)
      rescue
	trace = $!.backtrace
	raise $!, "\n#{trace[0]}: #{$!.message} (#{$!.class})\n" + 
	          "\tfrom #{trace[1..pos].join("\n\tfrom ")}"
      end
    end
  end

  def load_cmd_on_ip(tk_cmd)
    bool(tk_call('auto_load', tk_cmd))
  end

  def after(ms, cmd=Proc.new)
    myid = _curr_cmd_id
    cmdid = install_cmd(cmd)
    tk_call("after",ms,cmdid)
#    return
#    if false #defined? Thread
#      Thread.start do
#	ms = Float(ms)/1000
#	ms = 10 if ms == 0
#	sleep ms/1000
#	cmd.call
#      end
#    else
#      cmdid = install_cmd(cmd)
#      tk_call("after",ms,cmdid)
#    end
  end

  def after_idle(cmd=Proc.new)
    myid = _curr_cmd_id
    cmdid = install_cmd(cmd)
    tk_call('after','idle',cmdid)
  end

  def clock_clicks(ms=nil)
    if ms
      tk_call('clock','clicks','-milliseconds').to_i
    else
      tk_call('clock','clicks').to_i
    end
  end

  def clock_format(clk, form=nil)
    if form
      tk_call('clock','format',clk,'-format',form).to_i
    else
      tk_call('clock','format',clk).to_i
    end
  end

  def clock_formatGMT(clk, form=nil)
    if form
      tk_call('clock','format',clk,'-format',form,'-gmt','1').to_i
    else
      tk_call('clock','format',clk,'-gmt','1').to_i
    end
  end

  def clock_scan(str, base=nil)
    if base
      tk_call('clock','scan',str,'-base',base).to_i
    else
      tk_call('clock','scan',str).to_i
    end
  end

  def clock_scanGMT(str, base=nil)
    if base
      tk_call('clock','scan',str,'-base',base,'-gmt','1').to_i
    else
      tk_call('clock','scan',str,'-gmt','1').to_i
    end
  end

  def clock_seconds
    tk_call('clock','seconds').to_i
  end

  def windowingsystem
    tk_call('tk', 'windowingsystem')
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
    args = args.collect!{|c| _get_eval_string(c).gsub(/[\[\]$"]/, '\\\\\&')}
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
    args = args.collect!{|c| _get_eval_string(c).gsub(/[\[\]$"]/, '\\\\\&')}
    args.push(').to_s"')
    appsend_displayof(interp, win, async, 'ruby "(', *args)
  end

  def info(*args)
    tk_call('info', *args)
  end

  def mainloop(check_root = true)
    TclTkLib.mainloop(check_root)
  end

  def mainloop_watchdog(check_root = true)
    # watchdog restarts mainloop when mainloop is dead
    TclTkLib.mainloop_watchdog(check_root)
  end

  def do_one_event(flag = TclTkLib::EventFlag::ALL)
    TclTkLib.do_one_event(flag)
  end

  def set_eventloop_tick(timer_tick)
    TclTkLib.set_eventloop_tick(timer_tick)
  end

  def get_eventloop_tick()
    TclTkLib.get_eventloop_tick
  end

  def set_no_event_wait(wait)
    TclTkLib.set_no_even_wait(wait)
  end

  def get_no_event_wait()
    TclTkLib.get_no_eventloop_wait
  end

  def set_eventloop_weight(loop_max, no_event_tick)
    TclTkLib.set_eventloop_weight(loop_max, no_event_tick)
  end

  def get_eventloop_weight()
    TclTkLib.get_eventloop_weight
  end

  def restart(app_name = nil, keys = {})
    TkCore::INTERP.init_ip_internal

    tk_call('set', 'argv0', app_name) if app_name
    if keys.kind_of?(Hash)
      # tk_call('set', 'argc', keys.size * 2)
      tk_call('set', 'argv', hash_kv(keys).join(' '))
    end

    INTERP.restart
    nil
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

  def chooseDirectory(keys = nil)
    tk_call 'tk_chooseDirectory', *hash_kv(keys)
  end

  def ip_eval(cmd_string)
    res = INTERP._eval(cmd_string)
    if  INTERP._return_value() != 0
      fail RuntimeError, res, error_at
    end
    return res
  end

  def ip_invoke(*args)
    res = INTERP._invoke(*args)
    if  INTERP._return_value() != 0
      fail RuntimeError, res, error_at
    end
    return res
  end

  def tk_call(*args)
    puts args.inspect if $DEBUG
    args.collect! {|x|ruby2tcl(x)}
    args.compact!
    args.flatten!
    print "=> ", args.join(" ").inspect, "\n" if $DEBUG
    begin
      # res = INTERP._invoke(*args).taint
      res = INTERP._invoke(*args)   # _invoke returns a TAINTED string
    rescue NameError => err
#      err = $!
      begin
        args.unshift "unknown"
        #res = INTERP._invoke(*args).taint 
        res = INTERP._invoke(*args)   # _invoke returns a TAINTED string
      rescue StandardError => err2
	fail err2 unless /^invalid command/ =~ err2
	fail err
      end
    end
    if  INTERP._return_value() != 0
      fail RuntimeError, res, error_at
    end
    print "==> ", res.inspect, "\n" if $DEBUG
    return res
  end
end

module TkPackage
  include TkCore
  extend TkPackage

  TkCommandNames = ['package'.freeze].freeze

  def add_path(path)
    Tk::AUTO_PATH.value = Tk::AUTO_PATH.to_a << path
  end

  def forget(package)
    tk_call('package', 'forget', package)
    nil
  end

  def names
    tk_split_simplelist(tk_call('package', 'names'))
  end

  def provide(package, version=nil)
    if version
      tk_call('package', 'provide', package, version)
      nil
    else
      tk_call('package', 'provide', package)
    end
  end

  def present(package, version=None)
    tk_call('package', 'present', package, version)
  end

  def present_exact(package, version)
    tk_call('package', 'present', '-exact', package, version)
  end

  def require(package, version=None)
    tk_call('package', 'require', package, version)
  end

  def require_exact(package, version)
    tk_call('package', 'require', '-exact', package, version)
  end

  def versions(package)
    tk_split_simplelist(tk_call('package', 'versions', package))
  end

  def vcompare(version1, version2)
    Integer(tk_call('package', 'vcompare', version1, version2))
  end

  def vsatisfies(version1, version2)
    bool(tk_call('package', 'vsatisfies', version1, version2))
  end
end

module Tk
  include TkCore
  extend Tk

  TCL_VERSION = INTERP._invoke("info", "tclversion").freeze
  TCL_PATCHLEVEL = INTERP._invoke("info", "patchlevel").freeze

  TK_VERSION  = INTERP._invoke("set", "tk_version").freeze
  TK_PATCHLEVEL  = INTERP._invoke("set", "tk_patchLevel").freeze

  JAPANIZED_TK = (INTERP._invoke("info", "commands", "kanji") != "").freeze

  def Tk.const_missing(sym)
    case(sym)
    when :TCL_LIBRARY
      INTERP._invoke("set", "tcl_library").freeze

    when :TK_LIBRARY
      INTERP._invoke("set", "tk_library").freeze

    when :LIBRARY
      INTERP._invoke("info", "library").freeze

    #when :PKG_PATH, :PACKAGE_PATH, :TCL_PACKAGE_PATH
    #  tk_split_simplelist(INTERP._invoke('set', 'tcl_pkgPath'))

    #when :LIB_PATH, :LIBRARY_PATH, :TCL_LIBRARY_PATH
    #  tk_split_simplelist(INTERP._invoke('set', 'tcl_libPath'))

    when :PLATFORM, :TCL_PLATFORM
      Hash[*tk_split_simplelist(INTERP._invoke('array', 'get', 
					       'tcl_platform'))]

    when :ENV
      Hash[*tk_split_simplelist(INTERP._invoke('array', 'get', 'env'))]

    #when :AUTO_PATH   #<=== 
    #  tk_split_simplelist(INTERP._invoke('set', 'auto_path'))

    #when :AUTO_OLDPATH
    #  tk_split_simplelist(INTERP._invoke('set', 'auto_oldpath'))

    when :AUTO_INDEX
      Hash[*tk_split_simplelist(INTERP._invoke('array', 'get', 'auto_index'))]

    when :PRIV, :PRIVATE, :TK_PRIV
      priv = {}
      if INTERP._invoke('info', 'vars', 'tk::Priv') != ""
	var_nam = 'tk::Priv'
      else
	var_nam = 'tkPriv'
      end
      Hash[*tk_split_simplelist(INTERP._invoke('array', 'get', 
					       var_nam))].each{|k,v|
	k.freeze
	case v
	when /^-?\d+$/
	  priv[k] = v.to_i
	when /^-?\d+\.?\d*(e[-+]?\d+)?$/
	  priv[k] = v.to_f
	else
	  priv[k] = v.freeze
	end
      }
      priv

    else
      raise NameError, 'uninitialized constant Tk::' + sym.id2name
    end
  end

  def root
    TkRoot.new
  end

  def Tk.bell(nice = false)
    if nice
      tk_call 'bell', '-nice'
    else
      tk_call 'bell'
    end
  end

  def Tk.bell_on_display(win, nice = false)
    if nice
      tk_call('bell', '-displayof', win, '-nice')
    else
      tk_call('bell', '-displayof', win)
    end
  end

  def Tk.destroy(*wins)
    tk_call('destroy', *wins)
  end

  def Tk.exit
    tk_call('destroy', '.')
  end

  def Tk.current_grabs
    tk_split_list(tk_call('grab', 'current'))
  end

  def Tk.focus(display=nil)
    if display == nil
      window(tk_call('focus'))
    else
      window(tk_call('focus', '-displayof', display))
    end
  end

  def Tk.focus_lastfor(win)
    window(tk_call('focus', '-lastfor', win))
  end

  def Tk.focus_next(win)
    TkManageFocus.next(win)
  end

  def Tk.focus_prev(win)
    TkManageFocus.prev(win)
  end

  def Tk.strictMotif(bool=None)
    bool(tk_call('set', 'tk_strictMotif', bool))
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

  def Tk.toUTF8(str,encoding)
    INTERP._toUTF8(str,encoding)
  end
  
  def Tk.fromUTF8(str,encoding)
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

  module Wm
    include TkComm

    TkCommandNames = ['wm'.freeze].freeze

    def aspect(*args)
      w = tk_call('wm', 'aspect', path, *args)
      if args.length == 0
	list(w) 
      else
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
	tk_call 'wm', 'client', path
      else
        name = '' if name == nil
	tk_call 'wm', 'client', path, name
	self
      end
    end
    def colormapwindows(*args)
      r = tk_call('wm', 'colormapwindows', path, *args)
      if args.size == 0
	list(r)
      else
	self
      end
    end
    def wm_command(value=nil)
      if value
	tk_call('wm', 'command', path, value)
	self
      else
	procedure(tk_call('wm', 'command', path))
      end
    end
    def deiconify(ex = true)
      tk_call('wm', 'deiconify', path) if ex
      self
    end
    def focusmodel(mode = nil)
      if mode
	tk_call 'wm', 'focusmodel', path, mode
	self
      else
	tk_call 'wm', 'focusmodel', path
      end
    end
    def frame
      tk_call('wm', 'frame', path)
    end
    def geometry(geom=nil)
      if geom
	tk_call('wm', 'geometry', path, geom)
	self
      else
	tk_call('wm', 'geometry', path)
      end
    end
    def grid(*args)
      w = tk_call('wm', 'grid', path, *args)
      if args.size == 0
	list(w) 
      else
	self
      end
    end
    def group(*args)
      w = tk_call('wm', 'group', path, *args)
      if args.size == 0
	window(w) 
      else
	self
      end
    end
    def iconbitmap(bmp=nil)
      if bmp
	tk_call 'wm', 'iconbitmap', path, bmp
	self
      else
	tk_call 'wm', 'iconbitmap', path
      end
    end
    def iconify(ex = true)
      tk_call('wm', 'iconify', path) if ex
      self
    end
    def iconmask(bmp=nil)
      if bmp
	tk_call 'wm', 'iconmask', path, bmp
	self
      else
	tk_call 'wm', 'iconmask', path
      end
    end
    def iconname(name=nil)
      if name
	tk_call 'wm', 'iconname', path, name
	self
      else
	tk_call 'wm', 'iconname', path
      end
    end
    def iconposition(*args)
      w = tk_call('wm', 'iconposition', path, *args)
      if args.size == 0
	list(w) 
      else
	self
      end
    end
    def iconwindow(*args)
      w = tk_call('wm', 'iconwindow', path, *args)
      if args.size == 0
	window(w)
      else
	self
      end
    end
    def maxsize(*args)
      w = tk_call('wm', 'maxsize', path, *args)
      if args.size == 0
	list(w) 
      else
	self
      end
    end
    def minsize(*args)
      w = tk_call('wm', 'minsize', path, *args)
      if args.size == 0
	list(w) 
      else
	self
      end
    end
    def overrideredirect(bool=None)
      if bool == None
	bool(tk_call('wm', 'overrideredirect', path))
      else
	tk_call 'wm', 'overrideredirect', path, bool
	self
      end
    end
    def positionfrom(who=None)
      if who == None
	r = tk_call('wm', 'positionfrom', path)
	(r == "")? nil: r
      else
	tk_call('wm', 'positionfrom', path, who)
	self
      end
    end
    def protocol(name=nil, cmd=nil)
      if cmd
	tk_call('wm', 'protocol', path, name, cmd)
	self
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
      else
	self
      end
    end
    def sizefrom(who=None)
      if who == None
	r = tk_call('wm', 'sizefrom', path)
	(r == "")? nil: r
      else
	tk_call('wm', 'sizefrom', path, who)
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
	tk_call 'wm', 'state', path, state
	self
      else
	tk_call 'wm', 'state', path
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
	tk_call('wm', 'transient', path, master)
	self
      else
	window(tk_call('wm', 'transient', path, master))
      end
    end
    def withdraw(ex = true)
      tk_call('wm', 'withdraw', path) if ex
      self
    end
  end
end

###########################################
#  string with Tcl's encoding
###########################################
module Tk
  class EncodedString < String
    @@enc_buf = '__rb_encoding_buffer__'

    def self.tk_escape(str)
      s = '"' + str.gsub(/[\[\]$"]/, '\\\\\&') + '"'
      TkCore::INTERP.__eval(Kernel.format('global %s; set %s %s', 
					  @@enc_buf, @@enc_buf, s))
    end

    def self.new(str, enc = Tk.encoding_system)
      obj = super(self.tk_escape(str))
      obj.instance_eval{@enc = enc}
      obj
    end

    def self.new_without_escape(str, enc = Tk.encoding_system)
      obj = super(str)
      obj.instance_eval{@enc = enc}
      obj
    end

    def encoding
      @enc
    end
  end
  def Tk.EncodedString(str, enc = Tk.encoding_system)
    Tk::EncodedString.new(str, enc)
  end

  class UTF8_String < EncodedString
    def self.new(str)
      super(str, 'utf-8')
    end
    def self.new_without_escape(str)
      super(str, 'utf-8')
    end
  end
  def Tk.UTF8_String(str)
    Tk::UTF8_String.new(str)
  end
end


###########################################
#  convert kanji string to/from utf-8
###########################################
if /^8\.[1-9]/ =~ Tk::TCL_VERSION && !Tk::JAPANIZED_TK
  class TclTkIp
    # from tkencoding.rb by ttate@jaist.ac.jp
    alias __eval _eval
    alias __invoke _invoke
    
    attr_accessor :encoding
    
    def _eval(cmd)
      if defined? @encoding
	if cmd.kind_of?(Tk::EncodedString)
	  _fromUTF8(__eval(_toUTF8(cmd, cmd.encoding)), @encoding)
	else
	  _fromUTF8(__eval(_toUTF8(cmd, @encoding)), @encoding)
	end
      else
	__eval(cmd)
      end
    end

    def _invoke(*cmds)
      if defined? @encoding
	cmds = cmds.collect{|cmd|
	  if cmd.kind_of?(Tk::EncodedString)
	    _toUTF8(cmd, cmd.encoding)
	  else
	    _toUTF8(cmd, @encoding)
	  end
	}
	_fromUTF8(__invoke(*cmds), @encoding)
      else
	__invoke(*cmds)
	end
    end
  end

  module Tk
    module Encoding
      extend Encoding

      TkCommandNames = ['encoding'.freeze].freeze

      def encoding=(name)
	TkCore::INTERP.encoding = name
      end

      def encoding
	TkCore::INTERP.encoding
      end

      def encoding_names
	tk_split_simplelist(tk_call('encoding', 'names'))
      end

      def encoding_system
	tk_call('encoding', 'system')
      end

      def encoding_system=(enc)
	tk_call('encoding', 'system', enc)
      end

      def encoding_convertfrom(str, enc=None)
	TkCore::INTERP.__invoke('encoding', 'convertfrom', enc, str)
      end
      alias encoding_convert_from encoding_convertfrom

      def encoding_convertto(str, enc=None)
	TkCore::INTERP.__invoke('encoding', 'convertto', enc, str)
      end
      alias encoding_convert_to encoding_convertto
    end

    extend Encoding
  end

  # estimate encoding
  case $KCODE
  when /^e/i  # EUC
    Tk.encoding = 'euc-jp'
  when /^s/i  # SJIS
    Tk.encoding = 'shiftjis'
  when /^u/i  # UTF8
    Tk.encoding = 'utf-8'
  else        # NONE
    begin
      Tk.encoding = Tk.encoding_system
    rescue StandardError, NameError
      Tk.encoding = 'utf-8'
    end
  end

else
  # dummy methods
  class TclTkIp
    alias __eval _eval
    alias __invoke _invoke
  end

  module Tk
    module Encoding
      extend Encoding

      def encoding=(name)
	nil
      end
      def encoding
	nil
      end
      def encoding_names
	nil
      end
      def encoding_system
	nil
      end
      def encoding_system=(enc)
	nil
      end

      def encoding_convertfrom(str, enc=None)
	str
      end
      alias encoding_convert_from encoding_convertfrom

      def encoding_convertto(str, enc=None)
	str
      end
      alias encoding_convert_to encoding_convertto
    end

    extend Encoding
  end
end

module TkBindCore
  def bind(context, cmd=Proc.new, args=nil)
    Tk.bind(self, context, cmd, args)
  end

  def bind_append(context, cmd=Proc.new, args=nil)
    Tk.bind_append(self, context, cmd, args)
  end

  def bind_remove(context)
    Tk.bind_remove(self, context)
  end

  def bindinfo(context=nil)
    Tk.bindinfo(self, context)
  end
end

class TkBindTag
  include TkBindCore

  #BTagID_TBL = {}
  BTagID_TBL = TkCore::INTERP.create_table
  Tk_BINDTAG_ID = ["btag".freeze, "00000".taint].freeze

  TkCore::INTERP.init_ip_env{ BTagID_TBL.clear }

  def TkBindTag.id2obj(id)
    BTagID_TBL[id]? BTagID_TBL[id]: id
  end

  def TkBindTag.new_by_name(name, *args, &b)
    return BTagID_TBL[name] if BTagID_TBL[name]
    self.new(*args, &b).instance_eval{
      BTagID_TBL.delete @id
      @id = name
      BTagID_TBL[@id] = self
    }
  end

  def initialize(*args, &b)
    @id = Tk_BINDTAG_ID.join
    Tk_BINDTAG_ID[1].succ!
    BTagID_TBL[@id] = self
    bind(*args, &b) if args != []
  end

  ALL = self.new_by_name('all')

  def name
    @id
  end

  def to_eval
    @id
  end

  def inspect
    Kernel.format "#<TkBindTag: %s>", @id
  end
end

class TkBindTagAll<TkBindTag
  def TkBindTagAll.new(*args, &b)
    $stderr.puts "Warning: TkBindTagALL is obsolete. Use TkBindTag::ALL\n"

    TkBindTag::ALL.bind(*args, &b) if args != []
    TkBindTag::ALL
  end
end

class TkDatabaseClass<TkBindTag
  def self.new(name, *args, &b)
    return BTagID_TBL[name] if BTagID_TBL[name]
    super(name, *args, &b)
  end

  def initialize(name, *args, &b)
    @id = name
    BTagID_TBL[@id] = self
    bind(*args, &b) if args != []
  end

  def inspect
    Kernel.format "#<TkDatabaseClass: %s>", @id
  end
end

class TkVariable
  include Tk
  extend TkCore

  include Comparable

  #TkCommandNames = ['tkwait'.freeze].freeze
  TkCommandNames = ['vwait'.freeze].freeze

  #TkVar_CB_TBL = {}
  #TkVar_ID_TBL = {}
  TkVar_CB_TBL = TkCore::INTERP.create_table
  TkVar_ID_TBL = TkCore::INTERP.create_table
  Tk_VARIABLE_ID = ["v".freeze, "00000".taint].freeze

  TkCore::INTERP.add_tk_procs('rb_var', 'args', 
	"ruby [format \"TkVariable.callback %%Q!%s!\" $args]")

  def TkVariable.callback(args)
    name1,name2,op = tk_split_list(args)
    if TkVar_CB_TBL[name1]
      _get_eval_string(TkVar_CB_TBL[name1].trace_callback(name2,op))
    else
      ''
    end
  end

  def initialize(val="")
    @id = Tk_VARIABLE_ID.join
    Tk_VARIABLE_ID[1].succ!
    TkVar_ID_TBL[@id] = self

    @trace_var  = nil
    @trace_elem = nil
    @trace_opts = nil

=begin
    if val == []
      # INTERP._eval(format('global %s; set %s(0) 0; unset %s(0)', 
      #	                    @id, @id, @id))
    elsif val.kind_of?(Array)
      a = []
      # val.each_with_index{|e,i| a.push(i); a.push(array2tk_list(e))}
      # s = '"' + a.join(" ").gsub(/[\[\]$"]/, '\\\\\&') + '"'
      val.each_with_index{|e,i| a.push(i); a.push(e)}
      s = '"' + array2tk_list(a).gsub(/[\[\]$"]/, '\\\\\&') + '"'
      INTERP._eval(format('global %s; array set %s %s', @id, @id, s))
    elsif  val.kind_of?(Hash)
      s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
                   .gsub(/[\[\]$"]/, '\\\\\&') + '"'
      INTERP._eval(format('global %s; array set %s %s', @id, @id, s))
    else
      s = '"' + _get_eval_string(val).gsub(/[\[\]$"]/, '\\\\\&') + '"'
      INTERP._eval(format('global %s; set %s %s', @id, @id, s))
    end
=end
    if  val.kind_of?(Hash)
      s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
                   .gsub(/[\[\]$"]/, '\\\\\&') + '"'
      INTERP._eval(Kernel.format('global %s; array set %s %s', @id, @id, s))
    else
      s = '"' + _get_eval_string(val).gsub(/[\[\]$"]/, '\\\\\&') + '"'
      INTERP._eval(Kernel.format('global %s; set %s %s', @id, @id, s))
    end
  end

  def wait(on_thread = false, check_root = false)
    if $SAFE >= 4
      fail SecurityError, "can't wait variable at $SAFE >= 4"
    end
    if on_thread
      if check_root
	INTERP._thread_tkwait('variable', @id)
      else
	INTERP._thread_vwait(@id)
      end
    else 
      if check_root
	INTERP._invoke('tkwait', 'variable', @id)
      else
	INTERP._invoke('vwait', @id)
      end
    end
  end
  def eventloop_wait(check_root = false)
    wait(false, check_root)
  end
  def thread_wait(check_root = false)
    wait(true, check_root)
  end
  def tkwait(on_thread = true)
    wait(on_thread, true)
  end
  def eventloop_tkwait
    wait(false, true)
  end
  def thread_tkwait
    wait(true, true)
  end

  def id
    @id
  end

  def value
    begin
      INTERP._eval(Kernel.format('global %s; set %s', @id, @id))
    rescue
      if INTERP._eval(Kernel.format('global %s; array exists %s', 
				    @id, @id)) != "1"
	fail
      else
	Hash[*tk_split_simplelist(INTERP._eval(Kernel.format('global %s; array get %s', @id, @id)))]
      end
    end
  end

  def value=(val)
    begin
      s = '"' + _get_eval_string(val).gsub(/[\[\]$"]/, '\\\\\&') + '"'
      INTERP._eval(Kernel.format('global %s; set %s %s', @id, @id, s))
    rescue
      if INTERP._eval(Kernel.format('global %s; array exists %s', 
				    @id, @id)) != "1"
	fail
      else
	if val == []
	  INTERP._eval(Kernel.format('global %s; unset %s; set %s(0) 0; unset %s(0)', @id, @id, @id, @id))
	elsif val.kind_of?(Array)
	  a = []
	  val.each_with_index{|e,i| a.push(i); a.push(array2tk_list(e))}
	  s = '"' + a.join(" ").gsub(/[\[\]$"]/, '\\\\\&') + '"'
	  INTERP._eval(Kernel.format('global %s; unset %s; array set %s %s', 
				     @id, @id, @id, s))
	elsif  val.kind_of?(Hash)
	  s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
	                        .gsub(/[\[\]$"]/, '\\\\\&') + '"'
	  INTERP._eval(Kernel.format('global %s; unset %s; array set %s %s', 
				     @id, @id, @id, s))
	else
	  fail
	end
      end
    end
  end

  def [](index)
    INTERP._eval(Kernel.format('global %s; set %s(%s)', 
			       @id, @id, _get_eval_string(index)))
  end

  def []=(index,val)
    INTERP._eval(Kernel.format('global %s; set %s(%s) %s', @id, @id, 
			       _get_eval_string(index), _get_eval_string(val)))
  end

  def numeric
    number(value)
  end
  def numeric=(val)
    case val
    when Numeric
      self.value=(val)
    when TkVariable
      self.value=(val.numeric)
    else
      raise ArgumentError, "Numeric is expected"
    end
  end

  def to_i
    number(value).to_i
  end

  def to_f
    number(value).to_f
  end

  def to_s
    string(value).to_s
  end

  def to_sym
    value.intern
  end

  def list
    tk_split_list(value)
  end
  alias to_a list

  def list=(val)
    case val
    when Array
      self.value=(val)
    when TkVariable
      self.value=(val.list)
    else
      raise ArgumentError, "Array is expected"
    end
  end

  def inspect
    Kernel.format "#<TkVariable: %s>", @id
  end

  def coerce(other)
    case other
    when TkVariable
      [other.value, self.value]
    when String
      [other, self.to_s]
    when Symbol
      [other, self.to_sym]
    when Integer
      [other, self.to_i]
    when Float
      [other, self.to_f]
    when Array
      [other, self.to_a]
    else
      [other, self.value]
    end
  end

  def &(other)
    if other.kind_of?(Array)
      self.to_a & other.to_a
    else
      self.to_i & other.to_i
    end
  end
  def |(other)
    if other.kind_of?(Array)
      self.to_a | other.to_a
    else
      self.to_i | other.to_i
    end
  end
  def +(other)
    case other
    when Array
      self.to_a + other
    when String
      self.value + other
    else
      begin
	number(self.value) + other
      rescue
	self.value + other.to_s
      end
    end
  end
  def -(other)
    if other.kind_of?(Array)
      self.to_a - other
    else
      number(self.value) - other
    end
  end
  def *(other)
    begin
      number(self.value) * other
    rescue
      self.value * other
    end
  end
  def /(other)
    number(self.value) / other
  end
  def %(other)
    begin
      number(self.value) % other
    rescue
      self.value % other
    end
  end
  def **(other)
    number(self.value) ** other
  end
  def =~(other)
    self.value =~ other
  end

  def ==(other)
    case other
    when TkVariable
      self.equal?(other)
    when String
      self.to_s == other
    when Symbol
      self.to_sym == other
    when Integer
      self.to_i == other
    when Float
      self.to_f == other
    when Array
      self.to_a == other
    when Hash
      self.value == other
    else
      false
    end
  end

  def zero?
    numeric.zero?
  end
  def nonzero?
    !(numeric.zero?)
  end

  def <=>(other)
    if other.kind_of?(TkVariable)
      begin
	val = other.numeric
	other = val
      rescue
	other = other.value
      end
    end
    if other.kind_of?(Numeric)
      begin
	return self.numeric <=> other
      rescue
	return self.value <=> other.to_s
      end
    else
      return self.value <=> other
    end
  end

  def to_eval
    @id
  end

  def unset(elem=nil)
    if elem
      INTERP._eval(Kernel.format('global %s; unset %s(%s)', 
				 @id, @id, tk_tcl2ruby(elem)))
    else
      INTERP._eval(Kernel.format('global %s; unset %s', @id, @id))
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
    @trace_var.each_with_index{|e,i| 
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
    @trace_elem[elem].each_with_index{|e,i| 
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
  def self.new(name, *args)
    return TkVar_ID_TBL[name] if TkVar_ID_TBL[name]
    super(name, *args)
  end

  def initialize(varname, val=nil)
    @id = varname
    TkVar_ID_TBL[@id] = self
    if val
      s = '"' + _get_eval_string(val).gsub(/[\[\]$"]/, '\\\\\&') + '"' #"
      INTERP._eval(Kernel.format('global %s; set %s %s', @id, @id, s))
    end
  end
end

module Tk
  begin
    auto_path = INTERP._invoke('set', 'auto_path')
  rescue
    begin
      auto_path = INTERP._invoke('set', 'env(TCLLIBPATH)')
    rescue
      auto_path = Tk::LIBRARY
    end
  end

  AUTO_PATH = TkVarAccess.new('auto_path', auto_path)

=begin
  AUTO_OLDPATH = tk_split_simplelist(INTERP._invoke('set', 'auto_oldpath'))
  AUTO_OLDPATH.each{|s| s.freeze}
  AUTO_OLDPATH.freeze
=end

  TCL_PACKAGE_PATH = TkVarAccess.new('tcl_pkgPath')
  PACKAGE_PATH = TCL_PACKAGE_PATH

  TCL_LIBRARY_PATH = TkVarAccess.new('tcl_libPath')
  LIBRARY_PATH = TCL_LIBRARY_PATH

  TCL_PRECISION = TkVarAccess.new('tcl_precision')
end

module TkSelection
  include Tk
  extend Tk

  TkCommandNames = ['selection'.freeze].freeze

  def self.clear(sel=nil)
    if sel
      tk_call 'selection', 'clear', '-selection', sel
    else
      tk_call 'selection', 'clear'
    end
  end
  def self.clear_on_display(win, sel=nil)
    if sel
      tk_call 'selection', 'clear', '-displayof', win, '-selection', sel
    else
      tk_call 'selection', 'clear', '-displayof', win
    end
  end
  def clear(sel=nil)
    TkSelection.clear_on_display(self, sel)
    self
  end

  def self.get(keys=nil)
    tk_call 'selection', 'get', *hash_kv(keys)
  end
  def self.get_on_display(win, keys=nil)
    tk_call 'selection', 'get', '-displayof', win, *hash_kv(keys)
  end
  def get(keys=nil)
    TkSelection.get_on_display(self, sel)
  end

  def self.handle(win, func=Proc.new, keys=nil, &b)
    if func.kind_of?(Hash) && keys == nil
      keys = func
      func = Proc.new(&b)
    end
    args = ['selection', 'handle']
    args += hash_kv(keys)
    args += [win, func]
    tk_call(*args)
  end
  def handle(func=Proc.new, keys=nil, &b)
    TkSelection.handle(self, func, keys, &b)
  end

  def self.get_owner(sel=nil)
    if sel
      window(tk_call('selection', 'own', '-selection', sel))
    else
      window(tk_call('selection', 'own'))
    end
  end
  def self.get_owner_on_display(win, sel=nil)
    if sel
      window(tk_call('selection', 'own', '-displayof', win, '-selection', sel))
    else
      window(tk_call('selection', 'own', '-displayof', win))
    end
  end
  def get_owner(sel=nil)
    TkSelection.get_owner_on_display(self, sel)
    self
  end

  def self.set_owner(win, keys=nil)
    tk_call('selection', 'own', *(hash_kv(keys) << win))
  end
  def set_owner(keys=nil)
    TkSelection.set_owner(self, keys)
    self
  end
end

module TkKinput
  include Tk
  extend Tk

  TkCommandNames = [
    'kinput_start'.freeze, 
    'kinput_send_spot'.freeze, 
    'kanjiInput'.freeze
  ].freeze

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

  TkCommandNames = ['imconfigure'.freeze].freeze

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

  def TkXIM.caret(window, keys=nil)
    if keys
      tk_call('tk', 'caret', window, *hash_kv(keys))
      self
    else
      lst = tk_split_list(tk_call('tk', 'caret', window))
      info = {}
      while key = lst.shift
	info[key[1..-1]] = lst.shift
      end
      info
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
    TkXIM.useinputmethods(self, value)
  end

  def caret(keys=nil)
    TkXIM.caret(self, keys=nil)
  end

  def imconfigure(slot, value=None)
    TkXIM.configinfo(self, slot, value)
  end

  def imconfiginfo(slot=nil)
    TkXIM.configinfo(self, slot)
  end
end

module TkWinfo
  include Tk
  extend Tk

  TkCommandNames = ['winfo'.freeze].freeze

  def TkWinfo.atom(name, win=nil)
    if win
      number(tk_call('winfo', 'atom', '-displayof', win, name))
    else
      number(tk_call('winfo', 'atom', name))
    end
  end
  def winfo_atom(name)
    TkWinfo.atom(name, self)
  end

  def TkWinfo.atomname(id, win=nil)
    if win
      tk_call('winfo', 'atomname', '-displayof', win, id)
    else
      tk_call('winfo', 'atomname', id)
    end
  end
  def winfo_atomname(id)
    TkWinfo.atomname(id, self)
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
  alias winfo_class winfo_classname

  def TkWinfo.colormapfull(window)
     bool(tk_call('winfo', 'colormapfull', window.path))
  end
  def winfo_colormapfull
    TkWinfo.colormapfull self
  end

  def TkWinfo.containing(rootX, rootY, win=nil)
    if win
      window(tk_call('winfo', 'containing', '-displayof', win, rootX, rootY))
    else
      window(tk_call('winfo', 'containing', rootX, rootY))
    end
  end
  def winfo_containing(x, y)
    TkWinfo.containing(x, y, self)
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

  def TkWinfo.fpixels(window, dist)
    number(tk_call('winfo', 'fpixels', window.path, dist))
  end
  def winfo_fpixels(dist)
    TkWinfo.fpixels self, dist
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

  def TkWinfo.widget(id, win=nil)
    if win
      window(tk_call('winfo', 'pathname', '-displayof', win, id))
    else
      window(tk_call('winfo', 'pathname', id))
    end
  end
  def winfo_widget(id)
    TkWinfo.widget id, self
  end

  def TkWinfo.pixels(window, dist)
    number(tk_call('winfo', 'pixels', window.path, dist))
  end
  def winfo_pixels(dist)
    TkWinfo.pixels self, dist
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
    tk_call('winfo', 'screenvisual', window.path)
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
    tk_call('winfo', 'visual', window.path)
  end
  def winfo_visual
    TkWinfo.visual self
  end

  def TkWinfo.visualid(window)
    tk_call('winfo', 'visualid', window.path)
  end
  def winfo_visualid
    TkWinfo.visualid self
  end

  def TkWinfo.visualsavailable(window, includeids=false)
    if includeids
      list(tk_call('winfo', 'visualsavailable', window.path, "includeids"))
    else
      list(tk_call('winfo', 'visualsavailable', window.path))
    end
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
    bool(tk_call('winfo', 'viewable', window.path))
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

  TkCommandNames = ['pack'.freeze].freeze

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

  def info(slave)
    ilist = list(tk_call('pack', 'info', slave.epath))
    info = {}
    while key = ilist.shift
      info[key[1..-1]] = ilist.shift
    end
    return info
  end

  def propagate(master, bool=None)
    if bool == None
      bool(tk_call('pack', 'propagate', master.epath))
    else
      tk_call('pack', 'propagate', master.epath, bool)
    end
  end

  def slaves(master)
    list(tk_call('pack', 'slaves', master.epath))
  end

  module_function :configure, :forget, :info, :propagate, :slaves
end

module TkGrid
  include Tk
  extend Tk

  TkCommandNames = ['grid'.freeze].freeze

  def bbox(*args)
    list(tk_call('grid', 'bbox', *args))
  end

  def configure(widget, *args)
    if args[-1].kind_of?(Hash)
      keys = args.pop
    end
    wins = []
    args.unshift(widget)
    for i in args
      case i
      when '-', 'x', '^'  # RELATIVE PLACEMENT
	wins.push(i)
      else
	wins.push(i.epath)
      end
    end
    tk_call "grid", 'configure', *(wins+hash_kv(keys))
  end

  def columnconfigure(master, index, args)
    tk_call "grid", 'columnconfigure', master, index, *hash_kv(args)
  end

  def rowconfigure(master, index, args)
    tk_call "grid", 'rowconfigure', master, index, *hash_kv(args)
  end

  def columnconfiginfo(master, index, slot=nil)
    if slot
      tk_call('grid', 'columnconfigure', master, index, "-#{slot}").to_i
    else
      ilist = list(tk_call('grid', 'columnconfigure', master, index))
      info = {}
      while key = ilist.shift
	info[key[1..-1]] = ilist.shift
      end
      info
    end
  end

  def rowconfiginfo(master, index, slot=nil)
    if slot
      tk_call('grid', 'rowconfigure', master, index, "-#{slot}").to_i
    else
      ilist = list(tk_call('grid', 'rowconfigure', master, index))
      info = {}
      while key = ilist.shift
	info[key[1..-1]] = ilist.shift
      end
      info
    end
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
    if bool == None
      bool(tk_call('grid', 'propagate', master.epath))
    else
      tk_call('grid', 'propagate', master.epath, bool)
    end
  end

  def remove(*args)
    tk_call 'grid', 'remove', *args
  end

  def size(master)
    list(tk_call('grid', 'size', master))
  end

  def slaves(master, args)
    list(tk_call('grid', 'slaves', master, *hash_kv(args)))
  end

  module_function :bbox, :forget, :propagate, :info
  module_function :remove, :size, :slaves, :location
  module_function :configure, :columnconfigure, :rowconfigure
  module_function :columnconfiginfo, :rowconfiginfo
end

module TkPlace
  include Tk
  extend Tk

  TkCommandNames = ['place'.freeze].freeze

  def configure(win, slot, value=None)
    if slot.kind_of? Hash
      tk_call 'place', 'configure', win.epath, *hash_kv(slot)
    else
      tk_call 'place', 'configure', win.epath, "-#{slot}", value
    end
  end

  def configinfo(win, slot = nil)
    # for >= Tk8.4a2 ?
    if slot
      conf = tk_split_list(tk_call('place', 'configure', 
				   win.epath, "-#{slot}") )
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_simplelist(tk_call('place', 'configure', 
				  win.epath)).collect{|conflist|
	conf = tk_split_simplelist(conflist)
	conf[0] = conf[0][1..-1]
	conf
      }
    end
  end

  def forget(win)
    tk_call 'place', 'forget', win
  end

  def info(win)
    ilist = list(tk_call('place', 'info', win.epath))
    info = {}
    while key = ilist.shift
      info[key[1..-1]] = ilist.shift
    end
    return info
  end

  def slaves(master)
    list(tk_call('place', 'slaves', master.epath))
  end

  module_function :configure, :configinfo, :forget, :info, :slaves
end

module TkOptionDB
  include Tk
  extend Tk

  TkCommandNames = ['option'.freeze].freeze

  module Priority
    WidgetDefault = 20
    StartupFile   = 40
    UserDefault   = 60
    Interactive   = 80
  end

  def add(pat, value, pri=None)
    if $SAFE >= 4
      fail SecurityError, "can't call 'TkOptionDB.add' at $SAFE >= 4"
    end
    tk_call 'option', 'add', pat, value, pri
  end
  def clear
    if $SAFE >= 4
      fail SecurityError, "can't call 'TkOptionDB.crear' at $SAFE >= 4"
    end
    tk_call 'option', 'clear'
  end
  def get(win, name, klass)
    tk_call('option', 'get', win ,name, klass)
  end
  def readfile(file, pri=None)
    tk_call 'option', 'readfile', file, pri
  end
  module_function :add, :clear, :get, :readfile

  def read_entries(file, f_enc=nil)
    if TkCore::INTERP.safe?
      fail SecurityError, 
	"can't call 'TkOptionDB.read_entries' on a safe interpreter"
    end

    i_enc = Tk.encoding()

    unless f_enc
      f_enc = i_enc
    end

    ent = []
    cline = ''
    open(file, 'r') {|f|
      while line = f.gets
	cline += line.chomp!
	case cline
	when /\\$/    # continue
	  cline.chop!
	  next
	when /^!/     # coment
	  cline = ''
	  next
	when /^([^:]+):\s(.*)$/
	  pat = $1
	  val = $2
	  p "ResourceDB: #{[pat, val].inspect}" if $DEBUG
	  pat = TkCore::INTERP._toUTF8(pat, f_enc)
	  pat = TkCore::INTERP._fromUTF8(pat, i_enc)
	  val = TkCore::INTERP._toUTF8(val, f_enc)
	  val = TkCore::INTERP._fromUTF8(val, i_enc)
	  ent << [pat, val]
	  cline = ''
	else          # unknown --> ignore
	  cline = ''
	  next
	end
      end
    }
    ent
  end
  module_function :read_entries
      
  def read_with_encoding(file, f_enc=nil, pri=None)
    # try to read the file as an OptionDB file
    readfile(file, pri).each{|pat, val|
      add(pat, val, pri)
    }

=begin
    i_enc = Tk.encoding()

    unless f_enc
      f_enc = i_enc
    end

    cline = ''
    open(file, 'r') {|f|
      while line = f.gets
	cline += line.chomp!
	case cline
	when /\\$/    # continue
	  cline.chop!
	  next
	when /^!/     # coment
	  cline = ''
	  next
	when /^([^:]+):\s(.*)$/
	  pat = $1
	  val = $2
	  p "ResourceDB: #{[pat, val].inspect}" if $DEBUG
	  pat = TkCore::INTERP._toUTF8(pat, f_enc)
	  pat = TkCore::INTERP._fromUTF8(pat, i_enc)
	  val = TkCore::INTERP._toUTF8(val, f_enc)
	  val = TkCore::INTERP._fromUTF8(val, i_enc)
	  add(pat, val, pri)
	  cline = ''
	else          # unknown --> ignore
	  cline = ''
	  next
	end
      end
    }
=end
  end
  module_function :read_with_encoding

  # support procs on the resource database
  @@resource_proc_class = Class.new
  class << @@resource_proc_class
    private :new
 
    CARRIER    = '.'.freeze
    METHOD_TBL = TkCore::INTERP.create_table
    ADD_METHOD = false
    SAFE_MODE  = 4

    def __closed_block_check__(str)
      depth = 0
      str.scan(/[{}]/){|x|
	if x == "{"
	  depth += 1
	elsif x == "}"
	  depth -= 1
	end
	if depth <= 0 && !($' =~ /\A\s*\Z/)
	  fail RuntimeError, "bad string for procedure : #{str.inspect}"
	end
      }
      str
    end

    def __check_proc_string__(str)
      # If you want to check the proc_string, do it in this method.
      # Please define this in the block given to 'new_proc_class' method. 
      str
    end

    def method_missing(id, *args)
      res_proc = self::METHOD_TBL[id]
      unless res_proc.kind_of? Proc
        if id == :new || !(self::METHOD_TBL.has_key?(id) || self::ADD_METHOD)
          raise NoMethodError, 
                "not support resource-proc '#{id.id2name}' for #{self.name}"
        end
        proc_str = TkOptionDB.get(self::CARRIER, id.id2name, '').strip
        proc_str = '{' + proc_str + '}' unless /\A\{.*\}\Z/ =~ proc_str
	proc_str = __closed_block_check__(proc_str)
        proc_str = __check_proc_string__(proc_str)
        res_proc = eval('Proc.new' + proc_str)
        self::METHOD_TBL[id] = res_proc
      end
      proc{
         $SAFE = self::SAFE_MODE
         res_proc.call(*args)
      }.call
    end

    private :__closed_block_check__, :__check_proc_string__, :method_missing
  end
  @@resource_proc_class.freeze

  def __create_new_class(klass, func, safe = 4, add = false, parent = nil)
    klass = klass.to_s if klass.kind_of? Symbol
    unless (?A..?Z) === klass[0]
      fail ArgumentError, "bad string '#{klass}' for class name"
    end
    unless func.kind_of? Array
      fail ArgumentError, "method-list must be Array"
    end
    func_str = func.join(' ')
    if parent == nil
      install_win(parent)
    elsif parent <= @@resource_proc_class
      install_win(parent::CARRIER)
    else
      fail ArgumentError, "parent must be Resource-Proc class"
    end
    carrier = Tk.tk_call('frame', @path, '-class', klass)

    body = <<-"EOD"
      class #{klass} < TkOptionDB.module_eval('@@resource_proc_class')
        CARRIER    = '#{carrier}'.freeze
        METHOD_TBL = TkCore::INTERP.create_table
        ADD_METHOD = #{add}
        SAFE_MODE  = #{safe}
        %w(#{func_str}).each{|f| METHOD_TBL[f.intern] = nil }
      end
    EOD

    if parent.kind_of?(Class) && parent <= @@resource_proc_class
      parent.class_eval(body)
      eval(parent.name + '::' + klass)
    else
      eval(body)
      eval('TkOptionDB::' + klass)
    end
  end
  module_function :__create_new_class
  private_class_method :__create_new_class

  def __remove_methods_of_proc_class(klass)
    # for security, make these methods invalid
    class << klass
      attr_reader :class_eval, :name, :superclass, 
	:ancestors, :const_defined?, :const_get, :const_set, 
	:constants, :included_modules, :instance_methods, 
	:method_defined?, :module_eval, :private_instance_methods, 
	:protected_instance_methods, :public_instance_methods, 
	:remove_const, :remove_method, :undef_method, 
	:to_s, :inspect, :display, :method, :methods, 
	:instance_eval, :instance_variables, :kind_of?, :is_a?,
	:private_methods, :protected_methods, :public_methods
    end
  end
  module_function :__remove_methods_of_proc_class
  private_class_method :__remove_methods_of_proc_class

  RAND_BASE_CNT = [0]
  RAND_BASE_HEAD = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  RAND_BASE_CHAR = RAND_BASE_HEAD + 'abcdefghijklmnopqrstuvwxyz0123456789_'
  def __get_random_basename
    name = '%s%03d' % [RAND_BASE_HEAD[rand(RAND_BASE_HEAD.size),1], 
                       RAND_BASE_CNT[0]]
    len = RAND_BASE_CHAR.size
    (6+rand(10)).times{
      name << RAND_BASE_CHAR[rand(len),1]
    }
    RAND_BASE_CNT[0] = RAND_BASE_CNT[0] + 1
    name
  end
  module_function :__get_random_basename
  private_class_method :__get_random_basename

  # define new proc class :
  # If you want to modify the new class or create a new subclass, 
  # you must do such operation in the block parameter. 
  # Because the created class is flozen after evaluating the block. 
  def new_proc_class(klass, func, safe = 4, add = false, parent = nil, &b)
    new_klass = __create_new_class(klass, func, safe, add, parent)
    new_klass.class_eval(&b) if block_given?
    __remove_methods_of_proc_class(new_klass)
    new_klass.freeze
    new_klass
  end
  module_function :new_proc_class

  def eval_under_random_base(parent = nil, &b)
    new_klass = __create_new_class(__get_random_basename(), 
				   [], 4, false, parent)
    ret = new_klass.class_eval(&b) if block_given?
    __remove_methods_of_proc_class(new_klass)
    new_klass.freeze
    ret
  end
  module_function :eval_under_random_base

  def new_proc_class_random(klass, func, safe = 4, add = false, &b)
    eval_under_random_base(){
      TkOption.new_proc_class(klass, func, safe, add, self, &b)
    }
  end
  module_function :new_proc_class_random
end
TkOption = TkOptionDB
TkResourceDB = TkOptionDB

module TkTreatFont
  def font_configinfo(name = nil)
    ret = TkFont.used_on(self.path)
    if ret == nil
=begin
      if name
	ret = name
      else
	ret = TkFont.init_widget_font(self.path, self.path, 'configure')
      end
=end
      ret = TkFont.init_widget_font(self.path, self.path, 'configure')
    end
    ret
  end
  alias fontobj font_configinfo

  def font_configure(slot)
    slot = _symbolkey2str(slot)

    if slot.key?('font')
      fnt = slot.delete('font')
      if fnt.kind_of? TkFont
	return fnt.call_font_configure(self.path, self.path,'configure',slot)
      else
	if fnt 
	  if (slot.key?('kanjifont') || 
	      slot.key?('latinfont') || 
	      slot.key?('asciifont'))
	    fnt = TkFont.new(fnt)

	    lfnt = slot.delete('latinfont')
	    lfnt = slot.delete('asciifont') if slot.key?('asciifont')
	    kfnt = slot.delete('kanjifont')

	    fnt.latin_replace(lfnt) if lfnt
	    fnt.kanji_replace(kfnt) if kfnt
	  else
	    slot['font'] = fnt
	    tk_call(self.path, 'configure', *hash_kv(slot))
	  end
	end
	return self
      end
    end

    lfnt = slot.delete('latinfont')
    lfnt = slot.delete('asciifont') if slot.key?('asciifont')
    kfnt = slot.delete('kanjifont')

    if lfnt && kfnt
      return TkFont.new(lfnt, kfnt).call_font_configure(self.path, self.path, 
							'configure', slot)
    end

    latinfont_configure(lfnt) if lfnt
    kanjifont_configure(kfnt) if kfnt
      
    tk_call(self.path, 'configure', *hash_kv(slot)) if slot != {}
    self
  end

  def latinfont_configure(ltn, keys=nil)
    if (fobj = TkFont.used_on(self.path))
      fobj = TkFont.new(fobj) # create a new TkFont object
    elsif Tk::JAPANIZED_TK
      fobj = fontobj          # create a new TkFont object
    else
      tk_call(self.path, 'configure', '-font', ltn)
      return self
    end

    if fobj.kind_of?(TkFont)
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

    return fobj.call_font_configure(self.path, self.path, 'configure', {})
  end
  alias asciifont_configure latinfont_configure

  def kanjifont_configure(knj, keys=nil)
    if (fobj = TkFont.used_on(self.path))
      fobj = TkFont.new(fobj) # create a new TkFont object
    elsif Tk::JAPANIZED_TK
      fobj = fontobj          # create a new TkFont object
    else
      tk_call(self.path, 'configure', '-font', knj)
      return self
    end

    if fobj.kind_of?(TkFont)
      if knj.kind_of? TkFont
	conf = {}
	knj.kanji_configinfo.each{|key,val| conf[key] = val}
	if keys
	  fobj.kanji_configure(conf.update(keys))
	else
	  fobj.kanji_configure(conf)
	end
      else
	fobj.kanji_replace(knj)
      end
    end

    return fobj.call_font_configure(self.path, self.path, 'configure', {})
  end

  def font_copy(window, tag=nil)
    if tag
      fnt = window.tagfontobj(tag).dup
    else
      fnt = window.fontobj.dup
    end
    fnt.call_font_configure(self.path, self.path, 'configure', {})
    self
  end

  def latinfont_copy(window, tag=nil)
    fontobj.dup.call_font_configure(self.path, self.path, 'configure', {})
    if tag
      fontobj.latin_replace(window.tagfontobj(tag).latin_font_id)
    else
      fontobj.latin_replace(window.fontobj.latin_font_id)
    end
    self
  end
  alias asciifont_copy latinfont_copy

  def kanjifont_copy(window, tag=nil)
    fontobj.dup.call_font_configure(self.path, self.path, 'configure', {})
    if tag
      fontobj.kanji_replace(window.tagfontobj(tag).kanji_font_id)
    else
      fontobj.kanji_replace(window.fontobj.kanji_font_id)
    end
    self
  end
end

module TkTreatItemFont
  def __conf_cmd(idx)
    raise NotImplementedError, "need to define `__conf_cmd'"
  end
  def __item_pathname(tagOrId)
    raise NotImplementedError, "need to define `__item_pathname'"
  end
  private :__conf_cmd, :__item_pathname

  def tagfont_configinfo(tagOrId, name = nil)
    pathname = __item_pathname(tagOrId)
    ret = TkFont.used_on(pathname)
    if ret == nil
=begin
      if name
	ret = name
      else
	ret = TkFont.init_widget_font(pathname, self.path, 
				      __conf_cmd(0), __conf_cmd(1), tagOrId)
      end
=end
      ret = TkFont.init_widget_font(pathname, self.path, 
				    __conf_cmd(0), __conf_cmd(1), tagOrId)
    end
    ret
  end
  alias tagfontobj tagfont_configinfo

  def tagfont_configure(tagOrId, slot)
    pathname = __item_pathname(tagOrId)
    slot = _symbolkey2str(slot)

    if slot.key?('font')
      fnt = slot.delete('font')
      if fnt.kind_of? TkFont
	return fnt.call_font_configure(pathname, self.path,
				       __conf_cmd(0), __conf_cmd(1), 
				       tagOrId, slot)
      else
	if fnt 
	  if (slot.key?('kanjifont') || 
	      slot.key?('latinfont') || 
	      slot.key?('asciifont'))
	    fnt = TkFont.new(fnt)

	    lfnt = slot.delete('latinfont')
	    lfnt = slot.delete('asciifont') if slot.key?('asciifont')
	    kfnt = slot.delete('kanjifont')

	    fnt.latin_replace(lfnt) if lfnt
	    fnt.kanji_replace(kfnt) if kfnt
	  end

	  slot['font'] = fnt
	  tk_call(self.path, __conf_cmd(0), __conf_cmd(1), 
		  tagOrId, *hash_kv(slot))
	end
	return self
      end
    end

    lfnt = slot.delete('latinfont')
    lfnt = slot.delete('asciifont') if slot.key?('asciifont')
    kfnt = slot.delete('kanjifont')

    if lfnt && kfnt
      return TkFont.new(lfnt, kfnt).call_font_configure(pathname, self.path,
							__conf_cmd(0), 
							__conf_cmd(1), 
							tagOrId, slot)
    end

    latintagfont_configure(tagOrId, lfnt) if lfnt
    kanjitagfont_configure(tagOrId, kfnt) if kfnt
      
    tk_call(self.path, __conf_cmd(0), __conf_cmd(1), 
	    tagOrId, *hash_kv(slot)) if slot != {}
    self
  end

  def latintagfont_configure(tagOrId, ltn, keys=nil)
    pathname = __item_pathname(tagOrId)
    if (fobj = TkFont.used_on(pathname))
      fobj = TkFont.new(fobj)    # create a new TkFont object
    elsif Tk::JAPANIZED_TK
      fobj = tagfontobj(tagOrId) # create a new TkFont object
    else
      tk_call(self.path, __conf_cmd(0), __conf_cmd(1), tagOrId, '-font', ltn)
      return self
    end

    if fobj.kind_of?(TkFont)
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

    return fobj.call_font_configure(pathname, self.path,
				    __conf_cmd(0), __conf_cmd(1), tagOrId, {})
  end
  alias asciitagfont_configure latintagfont_configure

  def kanjitagfont_configure(tagOrId, knj, keys=nil)
    pathname = __item_pathname(tagOrId)
    if (fobj = TkFont.used_on(pathname))
      fobj = TkFont.new(fobj)    # create a new TkFont object
    elsif Tk::JAPANIZED_TK
      fobj = tagfontobj(tagOrId) # create a new TkFont object
    else
      tk_call(self.path, __conf_cmd(0), __conf_cmd(1), tagOrId, '-font', knj)
      return self
    end

    if fobj.kind_of?(TkFont)
      if knj.kind_of? TkFont
	conf = {}
	knj.kanji_configinfo.each{|key,val| conf[key] = val}
	if keys
	  fobj.kanji_configure(conf.update(keys))
	else
	  fobj.kanji_configure(conf)
	end
      else
	fobj.kanji_replace(knj)
      end
    end

    return fobj.call_font_configure(pathname, self.path,
				    __conf_cmd(0), __conf_cmd(1), tagOrId, {})
  end

  def tagfont_copy(tagOrId, window, wintag=nil)
    pathname = __item_pathname(tagOrId)
    if wintag
      fnt = window.tagfontobj(wintag).dup
    else
      fnt = window.fontobj.dup
    end
    fnt.call_font_configure(pathname, self.path, 
			    __conf_cmd(0), __conf_cmd(1), tagOrId, {})
    return self
  end

  def latintagfont_copy(tagOrId, window, wintag=nil)
    pathname = __item_pathname(tagOrId)
    tagfontobj(tagOrId).dup.call_font_configure(pathname, self.path, 
						__conf_cmd(0), __conf_cmd(1), 
						tagOrId, {})
    if wintag
      tagfontobj(tagOrId).
	latin_replace(window.tagfontobj(wintag).latin_font_id)
    else
      tagfontobj(tagOrId).latin_replace(window.fontobj.latin_font_id)
    end
    self
  end
  alias asciitagfont_copy latintagfont_copy

  def kanjitagfont_copy(tagOrId, window, wintag=nil)
    pathname = __item_pathname(tagOrId)
    tagfontobj(tagOrId).dup.call_font_configure(pathname, self.path, 
						__conf_cmd(0), __conf_cmd(1), 
						tagOrId, {})
    if wintag
      tagfontobj(tagOrId).
	kanji_replace(window.tagfontobj(wintag).kanji_font_id)
    else
      tagfontobj(tagOrId).kanji_replace(window.fontobj.kanji_font_id)
    end
    self
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
	fail NameError, 
	     "undefined local variable or method `#{name}' for #{self.to_s}", 
	     error_at
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
    case slot.to_s
    when 'text', 'label', 'show', 'data', 'file'
      tk_call path, 'cget', "-#{slot}"
    when 'font', 'kanjifont'
      #fnt = tk_tcl2ruby(tk_call(path, 'cget', "-#{slot}"))
      fnt = tk_tcl2ruby(tk_call(path, 'cget', "-font"))
      unless fnt.kind_of?(TkFont)
	fnt = fontobj(fnt)
      end
      if slot == 'kanjifont' && JAPANIZED_TK && TK_VERSION =~ /^4\.*/
	# obsolete; just for compatibility
	fnt.kanji_font
      else
	fnt
      end
    else
      tk_tcl2ruby tk_call(path, 'cget', "-#{slot}")
    end
  end

  def configure(slot, value=None)
    if slot.kind_of? Hash
      if (slot['font'] || slot[:font] || 
          slot['kanjifont'] || slot[:kanjifont] || 
	  slot['latinfont'] || slot[:latinfont] || 
          slot['asciifont'] || slot[:asciifont] )
	font_configure(slot)
      elsif slot.size > 0
	tk_call path, 'configure', *hash_kv(slot)
      end

    else
      if (slot == 'font' || slot == :font || 
          slot == 'kanjifont' || slot == :kanjifont || 
	  slot == 'latinfont' || slot == :latinfont || 
          slot == 'asciifont' || slot == :asciifont )
	if value == None
	  fontobj
	else
	  font_configure({slot=>value})
	end
      else
	tk_call path, 'configure', "-#{slot}", value
      end
    end
    self
  end

  def configure_cmd(slot, value)
    configure slot, install_cmd(value)
  end

  def configinfo(slot = nil)
    if slot == 'font' || slot == :font || 
       slot == 'kanjifont' || slot == :kanjifont
      conf = tk_split_simplelist(tk_send('configure', "-#{slot}") )
      conf[0] = conf[0][1..-1]
      conf[4] = fontobj(conf[4])
      conf
    else
      if slot
	case slot.to_s
	when 'text', 'label', 'show', 'data', 'file'
	  conf = tk_split_simplelist(tk_send('configure', "-#{slot}") )
	else
	  conf = tk_split_list(tk_send('configure', "-#{slot}") )
	end
	conf[0] = conf[0][1..-1]
	conf
      else
	ret = tk_split_simplelist(tk_send('configure') ).collect{|conflist|
	  conf = tk_split_simplelist(conflist)
	  conf[0] = conf[0][1..-1]
	  case conf[0]
	  when 'text', 'label', 'show', 'data', 'file'
	  else
	    if conf[3]
	      if conf[3].index('{')
		conf[3] = tk_split_list(conf[3]) 
	      else
		conf[3] = tk_tcl2ruby(conf[3]) 
	      end
	    end
	    if conf[4]
	      if conf[4].index('{')
		conf[4] = tk_split_list(conf[4]) 
	      else
		conf[4] = tk_tcl2ruby(conf[4]) 
	      end
	    end
	  end
	  conf
	}
	fontconf = ret.assoc('font')
	if fontconf
	  ret.delete_if{|item| item[0] == 'font' || item[0] == 'kanjifont'}
	  fontconf[4] = fontobj(fontconf[4])
	  ret.push(fontconf)
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
      fail(ArgumentError, 
	   Kernel.format("type error (%s); must be TkVariable object", 
			 v.class))
    end
    v
  end
  private :tk_trace_variable

  def destroy
    # tk_call 'trace', 'vdelete', @tk_vn, 'w', @var_id if @var_id
  end
end

class TkWindow<TkObject
  include TkWinfo
  extend TkBindCore

  WidgetClassName = ''.freeze
  def self.to_eval
    self::WidgetClassName
  end

  def initialize(parent=nil, keys=nil)
    if parent.kind_of? Hash
      keys = _symbolkey2str(parent)
      parent = keys.delete('parent')
      widgetname = keys.delete('widgetname')
      install_win(if parent then parent.path end, widgetname)
      without_creating = keys.delete('without_creating')
      if without_creating && !widgetname 
        fail ArgumentError, 
             "if set 'without_creating' to true, need to define 'widgetname'"
      end
    elsif keys
      keys = _symbolkey2str(keys)
      widgetname = keys.delete('widgetname')
      install_win(if parent then parent.path end, widgetname)
      without_creating = keys.delete('without_creating')
      if without_creating && !widgetname 
        fail ArgumentError, 
             "if set 'without_creating' to true, need to define 'widgetname'"
      end
    else
      install_win(if parent then parent.path end)
    end
    if self.method(:create_self).arity == 0
      p 'create_self has no arg' if $DEBUG
      create_self unless without_creating
      if keys
        # tk_call @path, 'configure', *hash_kv(keys)
        configure(keys)
      end
    else
      p 'create_self has args' if $DEBUG
      fontkeys = {}
      if keys
        ['font', 'kanjifont', 'latinfont', 'asciifont'].each{|key|
          fontkeys[key] = keys.delete(key) if keys.key?(key)
        }
      end
      if without_creating && keys
        configure(keys)
      else
        create_self(keys)
      end
      font_configure(fontkeys) unless fontkeys.empty?
    end
  end

  def create_self
    fail RuntimeError, "TkWindow is an abstract class"
  end
  private :create_self

  def bind_class
    @db_class || self.class()
  end

  def database_classname
    TkWinfo.classname(self)
  end
  def database_class
    name = database_classname()
    if WidgetClassNames[name]
      WidgetClassNames[name]
    else
      TkDatabaseClass.new(name)
    end
  end
  def self.database_classname
    self::WidgetClassName
  end
  def self.database_class
    WidgetClassNames[self::WidgetClassName]
  end

  def pack(keys = nil)
    tk_call 'pack', epath, *hash_kv(keys)
    self
  end

  def pack_in(target, keys = nil)
    if keys
      keys = keys.dup
      keys['in'] = target
    else
      keys = {'in'=>target}
    end
    tk_call 'pack', epath, *hash_kv(keys)
    self
  end

  def unpack
    tk_call 'pack', 'forget', epath
    self
  end
  alias pack_forget unpack

  def pack_config(slot, value=None)
    if slot.kind_of? Hash
      tk_call 'pack', 'configure', epath, *hash_kv(slot)
    else
      tk_call 'pack', 'configure', epath, "-#{slot}", value
    end
  end

  def pack_info()
    ilist = list(tk_call('pack', 'info', epath))
    info = {}
    while key = ilist.shift
      info[key[1..-1]] = ilist.shift
    end
    return info
  end

  def pack_propagate(mode=None)
    if mode == None
      bool(tk_call('pack', 'propagate', epath))
    else
      tk_call('pack', 'propagate', epath, mode)
      self
    end
  end

  def pack_slaves()
    list(tk_call('pack', 'slaves', epath))
  end

  def grid(keys = nil)
    tk_call 'grid', epath, *hash_kv(keys)
    self
  end

  def grid_in(target, keys = nil)
    if keys
      keys = keys.dup
      keys['in'] = target
    else
      keys = {'in'=>target}
    end
    tk_call 'grid', epath, *hash_kv(keys)
    self
  end

  def ungrid
    tk_call 'grid', 'forget', epath
    self
  end
  alias grid_forget ungrid

  def grid_bbox(*args)
    list(tk_call('grid', 'bbox', epath, *args))
  end

  def grid_config(slot, value=None)
    if slot.kind_of? Hash
      tk_call 'grid', 'configure', epath, *hash_kv(slot)
    else
      tk_call 'grid', 'configure', epath, "-#{slot}", value
    end
  end

  def grid_columnconfig(index, keys)
    tk_call('grid', 'columnconfigure', epath, index, *hash_kv(keys))
  end

  def grid_rowconfig(index, keys)
    tk_call('grid', 'rowconfigure', epath, index, *hash_kv(keys))
  end

  def grid_columnconfiginfo(index, slot=nil)
    if slot
      tk_call('grid', 'columnconfigure', epath, index, "-#{slot}").to_i
    else
      ilist = list(tk_call('grid', 'columnconfigure', epath, index))
      info = {}
      while key = ilist.shift
	info[key[1..-1]] = ilist.shift
      end
      info
    end
  end

  def grid_rowconfiginfo(index, slot=nil)
    if slot
      tk_call('grid', 'rowconfigure', epath, index, "-#{slot}").to_i
    else
      ilist = list(tk_call('grid', 'rowconfigure', epath, index))
      info = {}
      while key = ilist.shift
	info[key[1..-1]] = ilist.shift
      end
      info
    end
  end

  def grid_info()
    list(tk_call('grid', 'info', epath))
  end

  def grid_location(x, y)
    list(tk_call('grid', 'location', epath, x, y))
  end

  def grid_propagate(mode=None)
    if mode == None
      bool(tk_call('grid', 'propagate', epath))
    else
      tk_call('grid', 'propagate', epath, mode)
      self
    end
  end

  def grid_remove()
    tk_call 'grid', 'remove', epath
    self
  end

  def grid_size()
    list(tk_call('grid', 'size', epath))
  end

  def grid_slaves(args)
    list(tk_call('grid', 'slaves', epath, *hash_kv(args)))
  end

  def place(keys = nil)
    tk_call 'place', epath, *hash_kv(keys)
    self
  end

  def place_in(target, keys = nil)
    if keys
      keys = keys.dup
      keys['in'] = target
    else
      keys = {'in'=>target}
    end
    tk_call 'place', epath, *hash_kv(keys)
    self
  end

  def unplace
    tk_call 'place', 'forget', epath
    self
  end
  alias place_forget unplace

  def place_config(slot, value=None)
    if slot.kind_of? Hash
      tk_call 'place', 'configure', epath, *hash_kv(slot)
    else
      tk_call 'place', 'configure', epath, "-#{slot}", value
    end
  end

  def place_configinfo(slot = nil)
    # for >= Tk8.4a2 ?
    if slot
      conf = tk_split_list(tk_call('place', 'configure', epath, "-#{slot}") )
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_simplelist(tk_call('place', 
				  'configure', epath)).collect{|conflist|
	conf = tk_split_simplelist(conflist)
	conf[0] = conf[0][1..-1]
	conf
      }
    end
  end

  def place_info()
    ilist = list(tk_call('place', 'info', epath))
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
      self
    elsif args.length == 1
      case args[0]
      when 'global', :global
	#return(tk_call('grab', 'set', '-global', path))
	tk_call('grab', 'set', '-global', path)
	return self
      when 'release', :release
	#return tk_call('grab', 'release', path)
	tk_call('grab', 'release', path)
	return self
      else
	val = tk_call('grab', args[0], path)
      end
      case args[0]
      when 'current', :current
	return window(val)
      when 'status', :status
	return val
      end
      self
    else
      fail ArgumentError, 'wrong # of args'
    end
  end

  def grab_current
    grab('current')
  end
  def grab_release
    grab('release')
  end
  def grab_set
    grab('set')
  end
  def grab_set_global
    grab('global')
  end
  def grab_status
    grab('status')
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

  def caret(keys=nil)
    TkXIM.caret(path, keys)
  end

  def destroy
    super
    children = []
    rexp = /^#{self.path}\.[^.]+$/
    TkCore::INTERP.tk_windows.each{|path, obj|
      children << [path, obj] if path =~ rexp
    }
    if defined?(@cmdtbl)
      for id in @cmdtbl
	uninstall_cmd id
      end
    end

    children.each{|path, obj|
      if defined?(@cmdtbl)
	for id in @cmdtbl
	  uninstall_cmd id
	end
      end
      TkCore::INTERP.tk_windows.delete(path)
    }

    begin
      tk_call 'destroy', epath
    rescue
    end
    uninstall_win
  end

  def wait_visibility(on_thread = true)
    if $SAFE >= 4
      fail SecurityError, "can't wait visibility at $SAFE >= 4"
    end
    if on_thread
      INTERP._thread_tkwait('visibility', path)
    else
      INTERP._invoke('tkwait', 'visibility', path)
    end
  end
  def eventloop_wait_visibility
    wait_visibility(false)
  end
  def thread_wait_visibility
    wait_visibility(true)
  end
  alias wait wait_visibility
  alias tkwait wait_visibility
  alias eventloop_wait eventloop_wait_visibility
  alias eventloop_tkwait eventloop_wait_visibility
  alias eventloop_tkwait_visibility eventloop_wait_visibility
  alias thread_wait thread_wait_visibility
  alias thread_tkwait thread_wait_visibility
  alias thread_tkwait_visibility thread_wait_visibility

  def wait_destroy(on_thread = true)
    if $SAFE >= 4
      fail SecurityError, "can't wait destroy at $SAFE >= 4"
    end
    if on_thread
      INTERP._thread_tkwait('window', epath)
    else
      INTERP._invoke('tkwait', 'window', epath)
    end
  end
  def eventloop_wait_destroy
    wait_destroy(false)
  end
  def thread_wait_destroy
    wait_destroy(true)
  end
  alias tkwait_destroy wait_destroy
  alias eventloop_tkwait_destroy eventloop_wait_destroy
  alias thread_tkwait_destroy thread_wait_destroy

  def bindtags(taglist=nil)
    if taglist
      fail ArgumentError, "taglist must be Array" unless taglist.kind_of? Array
      tk_call('bindtags', path, taglist)
      taglist
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

  def bindtags=(taglist)
    bindtags(taglist)
  end

  def bindtags_shift
    taglist = bindtags
    tag = taglist.shift
    bindtags(taglist)
    tag
  end

  def bindtags_unshift(tag)
    bindtags(bindtags().unshift(tag))
  end
end

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
	super(:without_creating=>true, :widgetname=>'.')
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

class TkToplevel<TkWindow
  include Wm

  TkCommandNames = ['toplevel'.freeze].freeze
  WidgetClassName = 'Toplevel'.freeze
  WidgetClassNames[WidgetClassName] = self

################# old version
#  def initialize(parent=nil, screen=nil, classname=nil, keys=nil)
#    if screen.kind_of? Hash
#      keys = screen.dup
#    else
#      @screen = screen
#    end
#    @classname = classname
#    if keys.kind_of? Hash
#      keys = keys.dup
#      @classname = keys.delete('classname') if keys.key?('classname')
#      @colormap  = keys.delete('colormap')  if keys.key?('colormap')
#      @container = keys.delete('container') if keys.key?('container')
#      @screen    = keys.delete('screen')    if keys.key?('screen')
#      @use       = keys.delete('use')       if keys.key?('use')
#      @visual    = keys.delete('visual')    if keys.key?('visual')
#    end
#    super(parent, keys)
#  end
#
#  def create_self
#    s = []
#    s << "-class"     << @classname if @classname
#    s << "-colormap"  << @colormap  if @colormap
#    s << "-container" << @container if @container
#    s << "-screen"    << @screen    if @screen 
#    s << "-use"       << @use       if @use
#    s << "-visual"    << @visual    if @visual
#    tk_call 'toplevel', @path, *s
#  end
#################

  def _wm_command_option_chk(keys)
    keys = {} unless keys
    new_keys = {}
    wm_cmds = {}
    keys.each{|k,v|
      if Wm.method_defined?(k)
	case k
	when 'screen','class','colormap','container','use','visual'
	  new_keys[k] = v
	else
	  case self.method(k).arity
	  when -1,1
	    wm_cmds[k] = v
	  else
	    new_keys[k] = v
	  end
	end
      else
	new_keys[k] = v
      end
    }
    [new_keys, wm_cmds]
  end
  private :_wm_command_option_chk

  def initialize(parent=nil, screen=nil, classname=nil, keys=nil)
    my_class_name = nil
    if self.class < WidgetClassNames[WidgetClassName]
      my_class_name = self.class.name
      my_class_name = nil if my_class_name == ''
    end
    if parent.kind_of? Hash
      keys = _symbolkey2str(parent)
      if keys.key?('classname')
	keys['class'] = keys.delete('classname')
      end
      @classname = keys['class']
      @colormap  = keys['colormap']
      @container = keys['container']
      @screen    = keys['screen']
      @use       = keys['use']
      @visual    = keys['visual']
      if !@classname && my_class_name
	keys['class'] = @classname = my_class_name 
      end
      if @classname.kind_of? TkBindTag
	@db_class = @classname
	@classname = @classname.id
      elsif @classname
	@db_class = TkDatabaseClass.new(@classname)
      else
	@db_class = self.class
	@classname = @db_class::WidgetClassName
      end
      keys, cmds = _wm_command_option_chk(keys)
      super(keys)
      cmds.each{|k,v| 
	if v.kind_of? Array
	  self.send(k,*v)
	else
	  self.send(k,v)
	end
      }
      return
    end

    if screen.kind_of? Hash
      keys = screen
    else
      @screen = screen
      if classname.kind_of? Hash
	keys = classname
      else
	@classname = classname
      end
    end
    if keys.kind_of? Hash
      keys = _symbolkey2str(keys)
      if keys.key?('classname')
	keys['class'] = keys.delete('classname')
      end
      @classname = keys['class']  unless @classname
      @colormap  = keys['colormap']
      @container = keys['container']
      @screen    = keys['screen'] unless @screen
      @use       = keys['use']
      @visual    = keys['visual']
    else
      keys = {}
    end
    if !@classname && my_class_name
      keys['class'] = @classname = my_class_name 
    end
    if @classname.kind_of? TkBindTag
      @db_class = @classname
      @classname = @classname.id
    elsif @classname
      @db_class = TkDatabaseClass.new(@classname)
    else
      @db_class = self.class
      @classname = @db_class::WidgetClassName
    end
    keys, cmds = _wm_command_option_chk(keys)
    super(parent, keys)
    cmds.each{|k,v| 
      if v.kind_of? Array
	self.send(k,*v)
      else
	self.send(k,v)
      end
    }
  end

  def create_self(keys)
    if keys and keys != None
      tk_call 'toplevel', @path, *hash_kv(keys)
    else
      tk_call 'toplevel', @path
    end
  end
  private :create_self

  def specific_class
    @classname
  end

  def self.database_class
    if self == WidgetClassNames[WidgetClassName] || self.name == ''
      self
    else
      TkDatabaseClass.new(self.name)
    end
  end
  def self.database_classname
    self.database_class.name
  end

  def self.bind(*args)
    if self == WidgetClassNames[WidgetClassName] || self.name == ''
      super(*args)
    else
      TkDatabaseClass.new(self.name).bind(*args)
    end
  end
  def self.bind_append(*args)
    if self == WidgetClassNames[WidgetClassName] || self.name == ''
      super(*args)
    else
      TkDatabaseClass.new(self.name).bind_append(*args)
    end
  end
  def self.bind_remove(*args)
    if self == WidgetClassNames[WidgetClassName] || self.name == ''
      super(*args)
    else
      TkDatabaseClass.new(self.name).bind_remove(*args)
    end
  end
  def self.bindinfo(*args)
    if self == WidgetClassNames[WidgetClassName] || self.name == ''
      super(*args)
    else
      TkDatabaseClass.new(self.name).bindinfo(*args)
    end
  end
end

class TkFrame<TkWindow
  TkCommandNames = ['frame'.freeze].freeze
  WidgetClassName = 'Frame'.freeze
  WidgetClassNames[WidgetClassName] = self

################# old version
#  def initialize(parent=nil, keys=nil)
#    if keys.kind_of? Hash
#      keys = keys.dup
#      @classname = keys.delete('classname') if keys.key?('classname')
#      @colormap  = keys.delete('colormap')  if keys.key?('colormap')
#      @container = keys.delete('container') if keys.key?('container')
#      @visual    = keys.delete('visual')    if keys.key?('visual')
#    end
#    super(parent, keys)
#  end
#
#  def create_self
#    s = []
#    s << "-class"     << @classname if @classname
#    s << "-colormap"  << @colormap  if @colormap
#    s << "-container" << @container if @container
#    s << "-visual"    << @visual    if @visual
#    tk_call 'frame', @path, *s
#  end
#################

  def initialize(parent=nil, keys=nil)
    my_class_name = nil
    if self.class < WidgetClassNames[WidgetClassName]
      my_class_name = self.class.name
      my_class_name = nil if my_class_name == ''
    end
    if parent.kind_of? Hash
      keys = _symbolkey2str(parent)
    else
      if keys
        keys = _symbolkey2str(keys)
        keys['parent'] = parent
      else
        keys = {'parent'=>parent}
      end
    end
    if keys.key?('classname')
       keys['class'] = keys.delete('classname')
    end
    @classname = keys['class']
    @colormap  = keys['colormap']
    @container = keys['container']
    @visual    = keys['visual']
    if !@classname && my_class_name
      keys['class'] = @classname = my_class_name
    end
    if @classname.kind_of? TkBindTag
      @db_class = @classname
      @classname = @classname.id
    elsif @classname
      @db_class = TkDatabaseClass.new(@classname)
    else
      @db_class = self.class
      @classname = @db_class::WidgetClassName
    end
    super(keys)
  end

  def create_self(keys)
    if keys and keys != None
      tk_call 'frame', @path, *hash_kv(keys)
    else
      tk_call 'frame', @path
    end
  end
  private :create_self

  def database_classname
    @classname
  end

  def self.database_class
    if self == WidgetClassNames[WidgetClassName] || self.name == ''
      self
    else
      TkDatabaseClass.new(self.name)
    end
  end
  def self.database_classname
    self.database_class.name
  end

  def self.bind(*args)
    if self == WidgetClassNames[WidgetClassName] || self.name == ''
      super(*args)
    else
      TkDatabaseClass.new(self.name).bind(*args)
    end
  end
  def self.bind_append(*args)
    if self == WidgetClassNames[WidgetClassName] || self.name == ''
      super(*args)
    else
      TkDatabaseClass.new(self.name).bind_append(*args)
    end
  end
  def self.bind_remove(*args)
    if self == WidgetClassNames[WidgetClassName] || self.name == ''
      super(*args)
    else
      TkDatabaseClass.new(self.name).bind_remove(*args)
    end
  end
  def self.bindinfo(*args)
    if self == WidgetClassNames[WidgetClassName] || self.name == ''
      super(*args)
    else
      TkDatabaseClass.new(self.name).bindinfo(*args)
    end
  end
end

class TkLabelFrame<TkFrame
  TkCommandNames = ['labelframe'.freeze].freeze
  WidgetClassName = 'Labelframe'.freeze
  WidgetClassNames[WidgetClassName] = self
  def create_self(keys)
    if keys and keys != None
      tk_call 'labelframe', @path, *hash_kv(keys)
    else
      tk_call 'labelframe', @path
    end
  end
  private :create_self
end
TkLabelframe = TkLabelFrame

class TkPanedWindow<TkWindow
  TkCommandNames = ['panedwindow'.freeze].freeze
  WidgetClassName = 'Panedwindow'.freeze
  WidgetClassNames[WidgetClassName] = self
  def create_self(keys)
    if keys and keys != None
      tk_call 'panedwindow', @path, *hash_kv(keys)
    else
      tk_call 'panedwindow', @path
    end
  end
  private :create_self

  def add(*args)
    keys = args.pop
    fail ArgumentError, "no window in arguments" unless keys
    if keys && keys.kind_of?(Hash)
      fail ArgumentError, "no window in arguments" if args == []
      args = args.collect{|w| w.epath}
      args.push(hash_kv(keys))
    else
      args.push(keys) if keys
      args = args.collect{|w| w.epath}
    end
    tk_send('add', *args)
    self
  end

  def forget(win, *wins)
    tk_send('forget', win.epath, *(wins.collect{|w| w.epath}))
    self
  end
  alias del forget
  alias delete forget
  alias remove forget

  def identify(x, y)
    list(tk_send('identify', x, y))
  end

  def proxy_coord
    list(tk_send('proxy', 'coord'))
  end
  def proxy_forget
    tk_send('proxy', 'forget')
    self
  end
  def proxy_place(x, y)
    tk_send('proxy', 'place', x, y)
    self
  end

  def sash_coord(index)
    list(tk_send('sash', 'coord', index))
  end
  def sash_dragto(index)
    tk_send('sash', 'dragto', index, x, y)
    self
  end
  def sash_mark(index, x, y)
    tk_send('sash', 'mark', index, x, y)
    self
  end
  def sash_place(index, x, y)
    tk_send('sash', 'place', index, x, y)
    self
  end

  def panecget(win, key)
    tk_tcl2ruby(tk_send('panecget', win.epath, "-#{key}"))
  end

  def paneconfigure(win, key, value=nil)
    if key.kind_of? Hash
      tk_send('paneconfigure', win.epath, *hash_kv(key))
    else
      tk_send('paneconfigure', win.epath, "-#{key}", value)
    end
    self
  end
  alias pane_config paneconfigure

  def paneconfiginfo(win, key=nil)
    if key
      conf = tk_split_list(tk_send('paneconfigure', win.epath, "-#{key}"))
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_simplelist(tk_send('paneconfigure', 
				  win.epath)).collect{|conflist|
	conf = tk_split_simplelist(conflist)
	conf[0] = conf[0][1..-1]
	if conf[3]
	  if conf[3].index('{')
	    conf[3] = tk_split_list(conf[3]) 
	  else
	    conf[3] = tk_tcl2ruby(conf[3]) 
	  end
	end
	if conf[4]
	  if conf[4].index('{')
	    conf[4] = tk_split_list(conf[4]) 
	  else
	    conf[4] = tk_tcl2ruby(conf[4]) 
	  end
	end
	conf
      }
    end
  end
  alias pane_configinfo paneconfiginfo

  def panes
    list(tk_send('panes'))
  end
end
TkPanedwindow = TkPanedWindow

class TkLabel<TkWindow
  TkCommandNames = ['label'.freeze].freeze
  WidgetClassName = 'Label'.freeze
  WidgetClassNames[WidgetClassName] = self
  def create_self(keys)
    if keys and keys != None
      tk_call 'label', @path, *hash_kv(keys)
    else
      tk_call 'label', @path
    end
  end
  private :create_self

  def textvariable(v)
    configure 'textvariable', tk_trace_variable(v)
  end
end

class TkButton<TkLabel
  TkCommandNames = ['button'.freeze].freeze
  WidgetClassName = 'Button'.freeze
  WidgetClassNames[WidgetClassName] = self
  def create_self(keys)
    if keys and keys != None
      tk_call 'button', @path, *hash_kv(keys)
    else
      tk_call 'button', @path
    end
  end
  private :create_self

  def invoke
    tk_send 'invoke'
  end
  def flash
    tk_send 'flash'
    self
  end
end

class TkRadioButton<TkButton
  TkCommandNames = ['radiobutton'.freeze].freeze
  WidgetClassName = 'Radiobutton'.freeze
  WidgetClassNames[WidgetClassName] = self
  def create_self(keys)
    if keys and keys != None
      tk_call 'radiobutton', @path, *hash_kv(keys)
    else
      tk_call 'radiobutton', @path
    end
  end
  private :create_self

  def deselect
    tk_send 'deselect'
    self
  end
  def select
    tk_send 'select'
    self
  end
  def variable(v)
    configure 'variable', tk_trace_variable(v)
  end
end
TkRadiobutton = TkRadioButton

class TkCheckButton<TkRadioButton
  TkCommandNames = ['checkbutton'.freeze].freeze
  WidgetClassName = 'Checkbutton'.freeze
  WidgetClassNames[WidgetClassName] = self
  def create_self(keys)
    if keys and keys != None
      tk_call 'checkbutton', @path, *hash_kv(keys)
    else
      tk_call 'checkbutton', @path
    end
  end
  private :create_self

  def toggle
    tk_send 'toggle'
    self
  end
end
TkCheckbutton = TkCheckButton

class TkMessage<TkLabel
  TkCommandNames = ['message'.freeze].freeze
  WidgetClassName = 'Message'.freeze
  WidgetClassNames[WidgetClassName] = self
  def create_self(keys)
    if keys and keys != None
      tk_call 'message', @path, *hash_kv(keys)
    else
      tk_call 'message', @path
    end
  end
  private :create_self
end

class TkScale<TkWindow
  TkCommandNames = ['scale'.freeze].freeze
  WidgetClassName = 'Scale'.freeze
  WidgetClassNames[WidgetClassName] = self

  def create_self(keys)
    if keys and keys != None
      if keys.key?('command')
	cmd = keys.delete('command')
	keys['command'] = proc{|val| cmd.call(val.to_f)}
      end
      tk_call 'scale', @path, *hash_kv(keys)
    else
      tk_call 'scale', @path
    end
  end
  private :create_self

  def _wrap_command_arg(cmd)
    proc{|val|
      if val.kind_of?(String)
	cmd.call(number(val))
      else
	cmd.call(val)
      end
    }
  end
  private :_wrap_command_arg

  def configure_cmd(slot, value)
    configure(slot=>value)
  end

  def configure(slot, value=None)
    if (slot == 'command' || slot == :command)
      configure('command'=>value)
    elsif slot.kind_of?(Hash) && 
	(slot.key?('command') || slot.key?(:command))
      slot = _symbolkey2str(slot)
      slot['command'] = _wrap_command_arg(slot.delete('command'))
    end
    super(slot, value)
  end

  def command(cmd=Proc.new)
    configure('command'=>cmd)
  end

  def get(x=None, y=None)
    number(tk_send('get', x, y))
  end

  def coords(val=None)
    tk_split_list(tk_send('coords', val))
  end

  def identify(x, y)
    tk_send('identify', x, y)
  end

  def set(val)
    tk_send("set", val)
  end

  def value
    get
  end

  def value= (val)
    set(val)
  end
end

class TkScrollbar<TkWindow
  TkCommandNames = ['scrollbar'.freeze].freeze
  WidgetClassName = 'Scrollbar'.freeze
  WidgetClassNames[WidgetClassName] = self

  def create_self(keys)
    @assigned = []
    @scroll_proc = proc{|*args| 
      if self.orient == 'horizontal'
	@assigned.each{|w| w.xview(*args)}
      else # 'vertical'
	@assigned.each{|w| w.yview(*args)}
      end
    }

    if keys and keys != None
      tk_call 'scrollbar', @path, *hash_kv(keys)
    else
      tk_call 'scrollbar', @path
    end
  end
  private :create_self

  def assign(*wins)
    begin
      self.command(@scroll_proc) if self.cget('command').cmd != @scroll_proc
    rescue Exception
      self.command(@scroll_proc)
    end
    orient = self.orient
    wins.each{|w|
      @assigned << w unless @assigned.index(w)
      if orient == 'horizontal'
	w.xscrollcommand proc{|first, last| self.set(first, last)}
      else # 'vertical'
	w.yscrollcommand proc{|first, last| self.set(first, last)}
      end
    }
    self
  end

  def assigned_list
    begin
      return @assigned.dup if self.cget('command').cmd == @scroll_proc
    rescue Exception
    end
    fail RuntimeError, "not depend on the assigned_list"
  end

  def delta(deltax=None, deltay=None)
    number(tk_send('delta', deltax, deltay))
  end

  def fraction(x=None, y=None)
    number(tk_send('fraction', x, y))
  end

  def identify(x, y)
    tk_send('identify', x, y)
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
    self
  end

  def activate(element=None)
    tk_send('activate', element)
  end
end

class TkXScrollbar<TkScrollbar
  def create_self(keys)
    keys = {} unless keys
    keys['orient'] = 'horizontal'
    super(keys)
  end
  private :create_self
end

class TkYScrollbar<TkScrollbar
  def create_self(keys)
    keys = {} unless keys
    keys['orient'] = 'vertical'
    super(keys)
  end
  private :create_self
end

class TkTextWin<TkWindow
  def create_self
    fail RuntimeError, "TkTextWin is an abstract class"
  end
  private :create_self

  def bbox(index)
    list(tk_send('bbox', index))
  end
  def delete(first, last=None)
    tk_send 'delete', first, last
    self
  end
  def get(*index)
    tk_send 'get', *index
  end
  def insert(index, *args)
    tk_send 'insert', index, *args
    self
  end
  def scan_mark(x, y)
    tk_send 'scan', 'mark', x, y
    self
  end
  def scan_dragto(x, y)
    tk_send 'scan', 'dragto', x, y
    self
  end
  def see(index)
    tk_send 'see', index
    self
  end
end

module TkTreatListItemFont
  include TkTreatItemFont

  ItemCMD = ['itemconfigure'.freeze, TkComm::None].freeze
  def __conf_cmd(idx)
    ItemCMD[idx]
  end

  def __item_pathname(tagOrId)
    self.path + ';' + tagOrId.to_s
  end

  private :__conf_cmd, :__item_pathname
end

class TkListbox<TkTextWin
  include TkTreatListItemFont
  include Scrollable

  TkCommandNames = ['listbox'.freeze].freeze
  WidgetClassName = 'Listbox'.freeze
  WidgetClassNames[WidgetClassName] = self

  def create_self(keys)
    if keys and keys != None
      tk_call 'listbox', @path, *hash_kv(keys)
    else
      tk_call 'listbox', @path
    end
  end
  private :create_self

  def activate(y)
    tk_send 'activate', y
    self
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
    self
  end
  def selection_clear(first, last=None)
    tk_send 'selection', 'clear', first, last
    self
  end
  def selection_includes(index)
    bool(tk_send('selection', 'includes', index))
  end
  def selection_set(first, last=None)
    tk_send 'selection', 'set', first, last
    self
  end

  def index(index)
    tk_send('index', index).to_i
  end

  def itemcget(index, key)
    case key.to_s
    when 'text', 'label', 'show'
      tk_send('itemcget', index, "-#{key}")
    when 'font', 'kanjifont'
      #fnt = tk_tcl2ruby(tk_send('itemcget', index, "-#{key}"))
      fnt = tk_tcl2ruby(tk_send('itemcget', index, '-font'))
      unless fnt.kind_of?(TkFont)
	fnt = tagfontobj(index, fnt)
      end
      if key.to_s == 'kanjifont' && JAPANIZED_TK && TK_VERSION =~ /^4\.*/
	# obsolete; just for compatibility
	fnt.kanji_font
      else
	fnt
      end
    else
      tk_tcl2ruby(tk_send('itemcget', index, "-#{key}"))
    end
  end
  def itemconfigure(index, key, val=None)
    if key.kind_of? Hash
      if (key['font'] || key[:font] || 
          key['kanjifont'] || key[:kanjifont] || 
	  key['latinfont'] || key[:latinfont] || 
          key['asciifont'] || key[:asciifont] )
	tagfont_configure(index, _symbolkey2str(key))
      else
	tk_send 'itemconfigure', index, *hash_kv(key)
      end

    else
      if (key == 'font' || key == :font || 
          key == 'kanjifont' || key == :kanjifont || 
	  key == 'latinfont' || key == :latinfont || 
          key == 'asciifont' || key == :asciifont )
	if val == None
	  tagfontobj(index)
	else
	  tagfont_configure(index, {key=>val})
	end
      else
	tk_call 'itemconfigure', index, "-#{key}", val
      end
    end
    self
  end

  def itemconfiginfo(index, key=nil)
    if key
      case key.to_s
      when 'text', 'label', 'show'
	conf = tk_split_simplelist(tk_send('itemconfigure',index,"-#{key}"))
      when 'font', 'kanjifont'
	conf = tk_split_simplelist(tk_send('itemconfigure',index,"-#{key}") )
	conf[4] = tagfont_configinfo(index, conf[4])
      else
	conf = tk_split_list(tk_send('itemconfigure',index,"-#{key}"))
      end
      conf[0] = conf[0][1..-1]
      conf
    else
      ret = tk_split_simplelist(tk_send('itemconfigure', 
					index)).collect{|conflist|
	conf = tk_split_simplelist(conflist)
	conf[0] = conf[0][1..-1]
	case conf[0]
	when 'text', 'label', 'show'
	else
	  if conf[3]
	    if conf[3].index('{')
	      conf[3] = tk_split_list(conf[3]) 
	    else
	      conf[3] = tk_tcl2ruby(conf[3]) 
	    end
	  end
	  if conf[4]
	    if conf[4].index('{')
	      conf[4] = tk_split_list(conf[4]) 
	    else
	      conf[4] = tk_tcl2ruby(conf[4]) 
	    end
	  end
	end
	conf
      }
      fontconf = ret.assoc('font')
      if fontconf
	ret.delete_if{|item| item[0] == 'font' || item[0] == 'kanjifont'}
	fontconf[4] = tagfont_configinfo(index, fontconf[4])
	ret.push(fontconf)
      else
	ret
      end
    end
  end
end

module TkTreatMenuEntryFont
  include TkTreatItemFont

  ItemCMD = ['entryconfigure'.freeze, TkComm::None].freeze
  def __conf_cmd(idx)
    ItemCMD[idx]
  end
  
  def __item_pathname(tagOrId)
    self.path + ';' + tagOrId.to_s
  end

  private :__conf_cmd, :__item_pathname
end

class TkMenu<TkWindow
  include TkTreatMenuEntryFont

  TkCommandNames = ['menu'.freeze].freeze
  WidgetClassName = 'Menu'.freeze
  WidgetClassNames[WidgetClassName] = self

  def create_self(keys)
    if keys and keys != None
      tk_call 'menu', @path, *hash_kv(keys)
    else
      tk_call 'menu', @path
    end
  end
  private :create_self

  def activate(index)
    tk_send 'activate', index
    self
  end
  def add(type, keys=nil)
    tk_send 'add', type, *hash_kv(keys)
    self
  end
  def add_cascade(keys=nil)
    add('cascade', keys)
  end
  def add_checkbutton(keys=nil)
    add('checkbutton', keys)
  end
  def add_command(keys=nil)
    add('command', keys)
  end
  def add_radiobutton(keys=nil)
    add('radiobutton', keys)
  end
  def add_separator(keys=nil)
    add('separator', keys)
  end
  def index(index)
    ret = tk_send('index', index)
    (ret == 'none')? nil: number(ret)
  end
  def invoke(index)
    tk_send 'invoke', index
  end
  def insert(index, type, keys=nil)
    tk_send 'insert', index, type, *hash_kv(keys)
    self
  end
  def delete(index, last=None)
    tk_send 'delete', index, last
    self
  end
  def popup(x, y, index=None)
    tk_call('tk_popup', path, x, y, index)
    self
  end
  def post(x, y)
    tk_send 'post', x, y
    self
  end
  def postcascade(index)
    tk_send 'postcascade', index
    self
  end
  def postcommand(cmd=Proc.new)
    configure_cmd 'postcommand', cmd
    self
  end
  def set_focus
    tk_call('tk_menuSetFocus', path)
  end
  def tearoffcommand(cmd=Proc.new)
    configure_cmd 'tearoffcommand', cmd
    self
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
    case key.to_s
    when 'text', 'label', 'show'
      tk_send 'entrycget', index, "-#{key}"
    when 'font', 'kanjifont'
      #fnt = tk_tcl2ruby(tk_send('entrycget', index, "-#{key}"))
      fnt = tk_tcl2ruby(tk_send('entrycget', index, '-font'))
      unless fnt.kind_of?(TkFont)
	fnt = tagfontobj(index, fnt)
      end
      if key.to_s == 'kanjifont' && JAPANIZED_TK && TK_VERSION =~ /^4\.*/
	# obsolete; just for compatibility
	fnt.kanji_font
      else
	fnt
      end
    else
      tk_tcl2ruby(tk_send('entrycget', index, "-#{key}"))
    end
  end
  def entryconfigure(index, key, val=None)
    if key.kind_of? Hash
      if (key['font'] || key[:font] || 
          key['kanjifont'] || key[:kanjifont] || 
	  key['latinfont'] || key[:latinfont] || 
          key['asciifont'] || key[:asciifont])
	tagfont_configure(index, _symbolkey2str(key))
      else
	tk_send 'entryconfigure', index, *hash_kv(key)
      end

    else
      if (key == 'font' || key == :font || 
          key == 'kanjifont' || key == :kanjifont || 
	  key == 'latinfont' || key == :latinfont || 
          key == 'asciifont' || key == :asciifont )
	if val == None
	  tagfontobj(index)
	else
	  tagfont_configure(index, {key=>val})
	end
      else
	tk_call 'entryconfigure', index, "-#{key}", val
      end
    end
    self
  end

  def entryconfiginfo(index, key=nil)
    if key
      case key.to_s
      when 'text', 'label', 'show'
	conf = tk_split_simplelist(tk_send('entryconfigure',index,"-#{key}"))
      when 'font', 'kanjifont'
	conf = tk_split_simplelist(tk_send('entryconfigure',index,"-#{key}"))
	conf[4] = tagfont_configinfo(index, conf[4])
      else
	conf = tk_split_list(tk_send('entryconfigure',index,"-#{key}"))
      end
      conf[0] = conf[0][1..-1]
      conf
    else
      ret = tk_split_simplelist(tk_send('entryconfigure', 
					index)).collect{|conflist|
	conf = tk_split_simplelist(conflist)
	conf[0] = conf[0][1..-1]
	case conf[0]
	when 'text', 'label', 'show'
	else
	  if conf[3]
	    if conf[3].index('{')
	      conf[3] = tk_split_list(conf[3]) 
	    else
	      conf[3] = tk_tcl2ruby(conf[3]) 
	    end
	  end
	  if conf[4]
	    if conf[4].index('{')
	      conf[4] = tk_split_list(conf[4]) 
	    else
	      conf[4] = tk_tcl2ruby(conf[4]) 
	    end
	  end
	end
	conf
      }
      if fontconf
	ret.delete_if{|item| item[0] == 'font' || item[0] == 'kanjifont'}
	  fontconf[4] = tagfont_configinfo(index, fontconf[4])
	ret.push(fontconf)
      else
	ret
      end
    end
  end
end

class TkMenuClone<TkMenu
  def initialize(parent, type=None)
    widgetname = nil
    if parent.kind_of? Hash
      keys = _symbolkey2str(parent)
      parent = keys.delete('parent')
      widgetname = keys.delete('widgetname')
      type = keys.delete('type'); type = None unless type
    end
    unless parent.kind_of?(TkMenu)
      fail ArgumentError, "parent must be TkMenu"
    end
    @parent = parent
    install_win(@parent.path, widgetname)
    tk_call @parent.path, 'clone', @path, type
  end
end

module TkSystemMenu
  def initialize(parent, keys=nil)
    if parent.kind_of? Hash
      keys = _symbolkey2str(parent)
      parent = keys.delete('parent')
    end
    unless parent.kind_of? TkMenu
      fail ArgumentError, "parent must be a TkMenu object"
    end
    @path = Kernel.format("%s.%s", parent.path, self.class::SYSMENU_NAME)
    #TkComm::Tk_WINDOWS[@path] = self
    TkCore::INTERP.tk_windows[@path] = self
    if self.method(:create_self).arity == 0
      p 'create_self has no arg' if $DEBUG
      create_self
      configure(keys) if keys
    else
      p 'create_self has an arg' if $DEBUG
      create_self(keys)
    end
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
  TkCommandNames = ['menubutton'.freeze].freeze
  WidgetClassName = 'Menubutton'.freeze
  WidgetClassNames[WidgetClassName] = self
  def create_self(keys)
    if keys and keys != None
      tk_call 'menubutton', @path, *hash_kv(keys)
    else
      tk_call 'menubutton', @path
    end
  end
  private :create_self
end

class TkOptionMenubutton<TkMenubutton
  TkCommandNames = ['tk_optionMenu'.freeze].freeze

  class OptionMenu<TkMenu
    def initialize(path)  #==> return value of tk_optionMenu
      @path = path
      #TkComm::Tk_WINDOWS[@path] = self
      TkCore::INTERP.tk_windows[@path] = self
    end
  end

  def initialize(parent=nil, var=TkVariable.new, firstval=nil, *vals)
    if parent.kind_of? Hash
       keys = _symbolkey2str(parent)
       parent = keys['parent']
       var = keys['variable'] if keys['variable']
       firstval, *vals = keys['values']
    end
    fail 'variable option must be TkVariable' unless var.kind_of? TkVariable
    @variable = var
    firstval = @variable.value unless firstval
    @variable.value = firstval
    install_win(if parent then parent.path end)
    @menu = OptionMenu.new(tk_call('tk_optionMenu', @path, @variable.id, 
				   firstval, *vals))
  end

  def value
    @variable.value
  end

  def activate(index)
    @menu.activate(index)
    self
  end
  def add(value)
    @menu.add('radiobutton', 'variable'=>@variable, 
	      'label'=>value, 'value'=>value)
    self
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
    self
  end
  def delete(index, last=None)
    @menu.delete(index, last)
    self
  end
  def yposition(index)
    @menu.yposition(index)
  end
  def menu
    @menu
  end
  def menucget(key)
    @menu.cget(key)
  end
  def menuconfigure(key, val=None)
    @menu.configure(key, val)
    self
  end
  def menuconfiginfo(key=nil)
    @menu.configinfo(key)
  end
  def entrycget(index, key)
    @menu.entrycget(index, key)
  end
  def entryconfigure(index, key, val=None)
    @menu.entryconfigure(index, key, val)
    self
  end
  def entryconfiginfo(index, key=nil)
    @menu.entryconfiginfo(index, key)
  end
end

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

module TkClipboard
  include Tk
  extend Tk

  TkCommandNames = ['clipboard'.freeze].freeze

  def self.clear(win=nil)
    if win
      tk_call 'clipboard', 'clear', '-displayof', win
    else
      tk_call 'clipboard', 'clear'
    end
  end
  def self.clear_on_display(win)
    tk_call 'clipboard', 'clear', '-displayof', win
  end

  def self.get(type=nil)
    if type
      tk_call 'clipboard', 'get', '-type', type
    else
      tk_call 'clipboard', 'get'
    end
  end
  def self.get_on_display(win, type=nil)
    if type
      tk_call 'clipboard', 'get', '-displayof', win, '-type', type
    else
      tk_call 'clipboard', 'get', '-displayof', win
    end
  end

  def self.set(data, keys=nil)
    clear
    append(data, keys)
  end
  def self.set_on_display(win, data, keys=nil)
    clear(win)
    append_on_display(win, data, keys)
  end

  def self.append(data, keys=nil)
    args = ['clipboard', 'append']
    args += hash_kv(keys)
    args += ['--', data]
    tk_call(*args)
  end
  def self.append_on_display(win, data, keys=nil)
    args = ['clipboard', 'append', '-displayof', win]
    args += hash_kv(keys)
    args += ['--', data]
    tk_call(*args)
  end

  def clear
    TkClipboard.clear_on_display(self)
    self
  end
  def get(type=nil)
    TkClipboard.get_on_display(self, type)
  end
  def set(data, keys=nil)
    TkClipboard.set_on_display(self, data, keys)
    self
  end
  def append(data, keys=nil)
    TkClipboard.append_on_display(self, data, keys)
    self
  end
end

# widget_destroy_hook
require 'tkvirtevent'
TkBindTag::ALL.bind(TkVirtualEvent.new('Destroy'), proc{|xpath| 
		      path = xpath[1..-1]
		      if (widget = TkCore::INTERP.tk_windows[path])
			if widget.respond_to?(:__destroy_hook__)
			  begin
			    widget.__destroy_hook__
			  rescue Exception
			  end
			end
		      end
		    }, 'x%W')

# freeze core modules
#TclTkLib.freeze
#TclTkIp.freeze
#TkUtil.freeze
#TkKernel.freeze
#TkComm.freeze
#TkComm::Event.freeze
#TkCore.freeze
#Tk.freeze

# autoload
autoload :TkCanvas, 'tkcanvas'
autoload :TkImage, 'tkcanvas'
autoload :TkBitmapImage, 'tkcanvas'
autoload :TkPhotoImage, 'tkcanvas'
autoload :TkEntry, 'tkentry'
autoload :TkSpinbox, 'tkentry'
autoload :TkText, 'tktext'
autoload :TkDialog, 'tkdialog'
autoload :TkDialog2, 'tkdialog'
autoload :TkWarning, 'tkdialog'
autoload :TkWarning2, 'tkdialog'
autoload :TkMenubar, 'tkmenubar'
autoload :TkAfter, 'tkafter'
autoload :TkTimer, 'tkafter'
autoload :TkPalette, 'tkpalette'
autoload :TkFont, 'tkfont'
autoload :TkBgError, 'tkbgerror'
autoload :TkManageFocus, 'tkmngfocus'
autoload :TkPalette, 'tkpalette'
autoload :TkWinDDE, 'tkwinpkg'
autoload :TkWinRegistry, 'tkwinpkg'
autoload :TkMacResource, 'tkmacpkg'
autoload :TkConsole, 'tkconsole'
