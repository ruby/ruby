#
#   tracer.rb - 
#   	$Release Version: 0.2$
#   	$Revision: 1.1.1.1.4.1 $
#   	$Date: 1998/02/03 10:02:57 $
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
  RCS_ID='-$Id: tracer.rb,v 1.1.1.1.4.1 1998/02/03 10:02:57 matz Exp $-'
  
  MY_FILE_NAME = caller(0)[0].scan(/^(.*):[0-9]+$/)[0]
  
  EVENT_SYMBOL = {
    "line" => "-",
    "call" => ">",
    "return" => "<",
    "class" => "C",
    "end" => "E"}
  
  def initialize
    @threads = Hash.new
    if defined? Thread.main
      @threads[Thread.main.id] = 0
    else
      @threads[Thread.current.id] = 0
    end

    @sources = Hash.new
  end
  
  def on
    if iterator?
      on
      begin
	yield
      ensure
	off
      end
    else
      set_trace_func proc{|event, file, line, id, binding|
	trace_func event, file, line, id, binding
      }
      print "Trace on\n"
    end
  end
  
  def off
    set_trace_func nil
    print "Trace off\n"
  end
  
  def get_line(file, line)
    unless list = @sources[file]
#      print file if $DEBUG
      begin
	f = open(file)
	begin 
	  @sources[file] = list = f.readlines
	ensure
	  f.close
	end
      rescue
	@sources[file] = list = []
      end
    end
    if l = list[line - 1]
      l
    else
      "-\n"
    end
  end
  
  def get_thread_no
    if no = @threads[Thread.current.id]
      no
    else
      @threads[Thread.current.id] = @threads.size
    end
  end
  
  def trace_func(event, file, line, id, binding)
    return if file == MY_FILE_NAME
    #printf "Th: %s\n", Thread.current.inspect
    
    Thread.critical = TRUE
    printf("#%d:%s:%d:%s: %s",
	   get_thread_no,
	   file,
	   line,
	   EVENT_SYMBOL[event],
	   get_line(file, line))
    Thread.critical = FALSE
  end

  Single = new
  def Tracer.on
    Single.on
  end
  
  def Tracer.off
    Single.off
  end
  
end

if caller(0).size == 1
  if $0 == Tracer::MY_FILE_NAME
    # direct call
    
    $0 = ARGV[0]
    ARGV.shift
    Tracer.on
    require $0
  else
    Tracer.on
  end
end
