class Tracer
  MY_FILE_NAME_PATTERN = /^tracer\.(rb)?/
  Threads = Hash.new
  Sources = Hash.new
  
  EVENT_SYMBOL = {
    "line" => "-",
    "call" => ">",
    "return" => "<",
    "class" => "C",
    "end" => "E"}
  
  def on
    set_trace_func proc{|event, file, line, id, binding|
      trace_func event, file, line, id, binding
    }
    print "Trace on\n"
  end
  
  def off
    set_trace_func nil
    print "Trace off\n"
  end
  
  def get_thread_no
    unless no =  Threads[Thread.current.id]
      Threads[Thread.current.id] = no = Threads.size
    end
    no
  end
  
  def get_line(file, line)
    unless list = Sources[file]
      f =open(file)
      begin 
	Sources[file] = list = f.readlines
      ensure
	f.close
      end
    end
    list[line - 1]
  end
  
  def trace_func(event, file, line, id, binding)
    return if File.basename(file) =~ MY_FILE_NAME_PATTERN
    
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

if File.basename($0) =~ Tracer::MY_FILE_NAME_PATTERN
  $0 = ARGV.shift
  
  Tracer.on
  load $0
else
  Tracer.on
end
