#
#		tkcore.rb - Tk interface modue without thread
#			$Date: 1996/11/09 22:51:15 $
#			by Yukihiro Matsumoto <matz@caelum.co.jp>

require "tkutil"
if defined? Thread
  require "thread"
end

module Tk
  include TkUtil
  extend Tk

  wish_path = nil
  ENV['PATH'].split(":").each {|path|
    for wish in ['wish4.2', 'wish4.1', 'wish4.0', 'wish']
      if File.exist? path+'/'+wish
	wish_path = path+'/'+wish
	break
      end
      break if wish_path
    end
  }
  fail 'can\'t find wish' if not wish_path #'

  def Tk.tk_exit
    if not PORT.closed?
      PORT.print "exit\n"
      PORT.close
    end
  end

#  PORT = open(format("|%s -n %s", wish_path, File.basename($0)), "w+");
  PORT = open(format("|%s", wish_path), "w+");
  trap "EXIT", proc{Tk.tk_exit}
  trap "PIPE", ""

  def tk_write(*args)
    printf PORT, *args;
    PORT.print "\n"
    PORT.flush
  end
  tk_write '\
wm withdraw .
proc rb_out args {
  puts [format %%s $args]
  flush stdout
}
proc rb_ans arg {
  if [catch $arg var] {puts "!$var"} {puts "=$var@@"}
  flush stdout
}
proc tkerror args { exit }
proc keepalive {} { rb_out alive; after 120000 keepalive}
after 120000 keepalive'

  READABLE = []
  READ_CMD = {}

  def file_readable(port, cmd)
    if cmd == nil
      READABLE.delete port
    else
      READABLE.push port
    end
    READ_CMD[port] = cmd
  end

  WRITABLE = []
  WRITE_CMD = {}
  def file_writable(port, cmd)
    if cmd == nil
      WRITABLE.delete port
    else
      WRITABLE.push port
    end
    WRITE_CMD[port] = cmd
  end
  module_function :file_readable, :file_writable

  file_readable PORT, proc {
    line = PORT.gets
    exit if not line
    Tk.dispatch(line.chop!)
  }

  def error_at
    frames = caller(1)
    frames.delete_if do |c|
      c =~ %r!/tk(|core|thcore|canvas|text|entry|scrollbox)\.rb:\d+!
    end
    frames
  end

  def tk_tcl2ruby(val)
    case val
    when /^-?\d+$/
      val.to_i
    when /^\./
      $tk_window_list[val]
    when /^rb_out (c\d+)/
      $tk_cmdtbl[$1]
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
    idx = str.index('{')
    return tk_tcl2ruby(str) if not idx

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

  def bool(val)
    case bool
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
    tk_split_list(val)
  end
  def window(val)
    $tk_window_list[val]
  end
  def procedure(val)
    if val =~ /^rb_out (c\d+)/
      $tk_cmdtbl[$1]
    else
      nil
    end
  end
  private :bool, :number, :string, :list, :window, :procedure

  # mark for non-given arguments
  None = Object.new
  def None.to_s
    'None'
  end

  $tk_event_queue = []
  def tk_call(str, *args)
    args = args.collect{|s|
      next if s == None
      if s.kind_of?(Hash)
	s = hash_kv(s).join(" ")
      else
	if not s
	  s = "0"
	elsif s == TRUE
	  s = "1"
	elsif s.kind_of?(TkObject)
	  s = s.path
	elsif s.kind_of?(TkVariable)
	  s = s.id
	else
	  s = s.to_s
	  s.gsub!(/["\\\$\[\]]/, '\\\\\0') #"
	  s.gsub!(/\{/, '\\\\173')
	  s.gsub!(/\}/, '\\\\175')
	end
	"\"#{s}\""
      end
    }
    str += " "
    str += args.join(" ")
    print str, "\n" if $DEBUG
    tk_write 'rb_ans {%s}', str
    while PORT.gets
      print $_ if $DEBUG
      $_.chop!
      if /^=(.*)@@$/
	val = $1
	break
      elsif /^=/
	val = $' + "\n"
	while TRUE
	  PORT.readline
	  if ~/@@$/
	    val += $'
	    return val
	  else
	    val += $_
	  end
	end
      elsif /^!/
	$@ = error_at
	msg = $'
	if msg =~ /unknown option "-(.*)"/
	  $! = NameError.new(format("undefined method `%s' for %s(%s)",
				    $1, self, self.type)) #`'
	else
	  $! = RuntimeError.new(format("%s - %s", self.type, msg))
	end
	fail
      end
      $tk_event_queue.push $_
    end

    while ev = $tk_event_queue.shift
      Tk.dispatch ev
    end
    fail 'wish closed' if PORT.closed?
#    tk_split_list(val)
    val
  end

  def hash_kv(keys)
    conf = []
    if keys
      for k, v in keys
	 conf.push("-#{k}")
	 v = install_cmd(v) if v.kind_of? Proc
	 conf.push(v)
      end
    end
    conf
  end
  private :tk_call, :error_at, :hash_kv

  $tk_cmdid = 0
  def install_cmd(cmd)
    return '' if cmd == ''	# uninstall cmd
    id = format("c%.4d", $tk_cmdid)
    $tk_cmdid += 1
    $tk_cmdtbl[id] = cmd
    @cmdtbl = [] if not @cmdtbl
    @cmdtbl.push id
    return format('rb_out %s', id)
  end
  def uninstall_cmd(id)
    $tk_cmdtbl[id] = nil
  end
  private :install_cmd, :uninstall_cmd

  $tk_window_list = {}
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
      id + " %# %b %f %h %k %s %t %w %x %y %A %E %K %N %W %T %X %Y"
    end
  end

  def _bind(path, context, cmd, args=nil)
    begin
      id = install_bind(cmd, args)
      tk_call 'bind', path, "<#{context}>", id
    rescue
      $tk_cmdtbl[id] = nil
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

  $tk_cmdtbl = {}

  def after(ms, cmd=Proc.new)
    myid = format("c%.4d", $tk_cmdid)
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

  def dispatch(line)
    if line =~ /^c\d+/
      cmd = $&
      fail "no command `#{cmd}'" if not $tk_cmdtbl[cmd]
      args = tk_split_list($')
      TkUtil.eval_cmd $tk_cmdtbl[cmd], *args
    elsif line =~ /^alive$/
      # keep alive, do nothing
    else
      fail "malformed line <#{line}>"
    end
  end

  def mainloop
    begin
      tk_write 'after idle {wm deiconify .}'
      while TRUE
	rf, wf = select(READABLE, WRITABLE)
	for f in rf
	  READ_CMD[f].call(f) if READ_CMD[f]
	  if f.closed?
	    READABLE.delete f
	    READ_CMD[f] = nil
	  end
	end
	for f in wf
	  WRITE_CMD[f].call(f) if WRITE_CMD[f]
	  if f.closed?
	    WRITABLE.delete f
	    WRITE_CMD[f] = nil
	  end
	end
      end
    ensure
      Tk.tk_exit
    end
  end

  def root
    $tk_root
  end

  def bell
    tk_call 'bell'
  end
  module_function :after, :update, :dispatch, :mainloop, :root, :bell

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
      tk_call 'wm', 'iconify'
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
      tk_call 'wm', 'iconwindow', path, *args
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
