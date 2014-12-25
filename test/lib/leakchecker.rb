class LeakChecker
  def initialize
    @fd_info = find_fds
    @tempfile_info = find_tempfiles
    @thread_info = find_threads
  end

  def check(test_name)
    leaked1 = check_fd_leak(test_name)
    leaked2 = check_thread_leak(test_name)
    leaked3 = check_tempfile_leak(test_name)
    GC.start if leaked1 || leaked2 || leaked3
  end

  def find_fds
    fd_dir = "/proc/self/fd"
    if File.directory?(fd_dir)
      fds = Dir.open(fd_dir) {|d|
        a = d.grep(/\A\d+\z/, &:to_i)
        if d.respond_to? :fileno
          a -= [d.fileno]
        end
        a
      }
      fds.sort
    else
      []
    end
  end

  def check_fd_leak(test_name)
    leaked = false
    live1 = @fd_info
    if IO.respond_to?(:console)
      IO.console(:close)
    end
    live2 = find_fds
    fd_closed = live1 - live2
    if !fd_closed.empty?
      fd_closed.each {|fd|
        puts "Closed file descriptor: #{test_name}: #{fd}"
      }
    end
    fd_leaked = live2 - live1
    if !fd_leaked.empty?
      leaked = true
      h = {}
      ObjectSpace.each_object(IO) {|io|
        inspect = io.inspect
        begin
          autoclose = io.autoclose?
          fd = io.fileno
        rescue IOError # closed IO object
          next
        end
        (h[fd] ||= []) << [io, autoclose, inspect]
      }
      fd_leaked.each {|fd|
        str = ''
        if h[fd]
          str << ' :'
          h[fd].map {|io, autoclose, inspect|
            s = ' ' + inspect
            s << "(not-autoclose)" if !autoclose
            s
          }.sort.each {|s|
            str << s
          }
        end
        puts "Leaked file descriptor: #{test_name}: #{fd}#{str}"
      }
      #system("lsof -p #$$") if !fd_leaked.empty?
      h.each {|fd, list|
        next if list.length <= 1
        if 1 < list.count {|io, autoclose, inspect| autoclose }
          str = list.map {|io, autoclose, inspect| " #{inspect}" + (autoclose ? "(autoclose)" : "") }.sort.join
          puts "Multiple autoclose IO object for a file descriptor:#{str}"
        end
      }
    end
    @fd_info = live2
    return leaked
  end

  def extend_tempfile_counter
    return if defined? LeakChecker::TempfileCounter
    m = Module.new {
      @count = 0
      class << self
        attr_accessor :count
      end

      def new(data)
        LeakChecker::TempfileCounter.count += 1
        super(data)
      end
    }
    LeakChecker.const_set(:TempfileCounter, m)

    class << Tempfile::Remover
      prepend LeakChecker::TempfileCounter
    end
  end

  def find_tempfiles(prev_count=-1)
    return [prev_count, []] unless defined? Tempfile
    extend_tempfile_counter
    count = TempfileCounter.count
    if prev_count == count
      [prev_count, []]
    else
      tempfiles = ObjectSpace.each_object(Tempfile).find_all {|t| t.path }
      [count, tempfiles]
    end
  end

  def check_tempfile_leak(test_name)
    return false, @tempfile_info unless defined? Tempfile
    count1, initial_tempfiles = @tempfile_info
    count2, current_tempfiles = find_tempfiles(count1)
    leaked = false
    tempfiles_leaked = current_tempfiles - initial_tempfiles
    if !tempfiles_leaked.empty?
      leaked = true
      list = tempfiles_leaked.map {|t| t.inspect }.sort
      list.each {|str|
        puts "Leaked tempfile: #{test_name}: #{str}"
      }
      tempfiles_leaked.each {|t| t.close! }
    end
    @tempfile_info = [count2, initial_tempfiles]
    return leaked
  end

  def find_threads
    Thread.list.find_all {|t|
      t != Thread.current && /\AWEBrick::/ !~ t.class.name && t.alive?
    }
  end

  def check_thread_leak(test_name)
    live1 = @thread_info
    live2 = find_threads
    thread_finished = live1 - live2
    leaked = false
    if !thread_finished.empty?
      list = thread_finished.map {|t| t.inspect }.sort
      list.each {|str|
        puts "Finished thread: #{test_name}: #{str}"
      }
    end
    thread_leaked = live2 - live1
    if !thread_leaked.empty?
      leaked = true
      list = thread_leaked.map {|t| t.inspect }.sort
      list.each {|str|
        puts "Leaked thread: #{test_name}: #{str}"
      }
    end
    @thread_info = live2
    return leaked
  end

  def puts(*a)
    MiniTest::Unit.output.puts(*a)
  end
end
