#
#   tracer.rb -
#   	$Release Version: 0.2$
#   	$Revision: 1.8 $
#   	$Date: 1998/05/19 03:42:49 $
#   	by Keiju ISHITSUKA(Nippon Rational Inc.)
#
# --
#
#
#

#
# tracer main class
#
class Tracer
  @RCS_ID='-$Id: tracer.rb,v 1.8 1998/05/19 03:42:49 keiju Exp keiju $-'

  @stdout = STDOUT
  @verbose = false
  class << self
    attr :verbose, true
    alias verbose? verbose
    attr :stdout, true
  end

  EVENT_SYMBOL = {
    "line" => "-",
    "call" => ">",
    "return" => "<",
    "class" => "C",
    "end" => "E",
    "c-call" => ">",
    "c-return" => "<",
  }

  def initialize
    @threads = Hash.new
    if defined? Thread.main
      @threads[Thread.main.object_id] = 0
    else
      @threads[Thread.current.object_id] = 0
    end

    @get_line_procs = {}

    @filters = []
  end

  def stdout
    Tracer.stdout
  end

  def on
    if block_given?
      on
      begin
	yield
      ensure
	off
      end
    else
      set_trace_func method(:trace_func).to_proc
      stdout.print "Trace on\n" if Tracer.verbose?
    end
  end

  def off
    set_trace_func nil
    stdout.print "Trace off\n" if Tracer.verbose?
  end

  def add_filter(p = proc)
    @filters.push p
  end

  def set_get_line_procs(file, p = proc)
    @get_line_procs[file] = p
  end

  def get_line(file, line)
    if p = @get_line_procs[file]
      return p.call(line)
    end

    unless list = SCRIPT_LINES__[file]
      begin
	f = open(file)
	begin
	  SCRIPT_LINES__[file] = list = f.readlines
	ensure
	  f.close
	end
      rescue
	SCRIPT_LINES__[file] = list = []
      end
    end

    if l = list[line - 1]
      l
    else
      "-\n"
    end
  end

  def get_thread_no
    if no = @threads[Thread.current.object_id]
      no
    else
      @threads[Thread.current.object_id] = @threads.size
    end
  end

  def trace_func(event, file, line, id, binding, klass, *)
    return if file == __FILE__

    for p in @filters
      return unless p.call event, file, line, id, binding, klass
    end

    saved_crit = Thread.critical
    Thread.critical = true
    stdout.printf("#%d:%s:%d:%s:%s: %s",
      get_thread_no,
      file,
      line,
      klass || '',
      EVENT_SYMBOL[event],
      get_line(file, line))
    Thread.critical = saved_crit
  end

  Single = new
  def Tracer.on
    if block_given?
      Single.on{yield}
    else
      Single.on
    end
  end

  def Tracer.off
    Single.off
  end

  def Tracer.set_get_line_procs(file_name, p = proc)
    Single.set_get_line_procs(file_name, p)
  end

  def Tracer.add_filter(p = proc)
    Single.add_filter(p)
  end

end

SCRIPT_LINES__ = {} unless defined? SCRIPT_LINES__

if $0 == __FILE__
  # direct call

  $0 = ARGV[0]
  ARGV.shift
  Tracer.on
  require $0
elsif caller(0).size == 1
  Tracer.on
end
