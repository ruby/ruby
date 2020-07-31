# frozen_string_literal: true
class LeakChecker
  @@try_lsof = nil # not-tried-yet

  def initialize
    @fd_info = find_fds
    @@skip = false
    @tempfile_info = find_tempfiles
    @thread_info = find_threads
    @env_info = find_env
    @encoding_info = find_encodings
    @old_verbose = $VERBOSE
    @old_warning_flags = find_warning_flags
  end

  def check(test_name)
    if /i386-solaris/ =~ RUBY_PLATFORM && /TestGem/ =~ test_name
      GC.verify_internal_consistency
    end

    leaks = [
      check_fd_leak(test_name),
      check_thread_leak(test_name),
      check_tempfile_leak(test_name),
      check_env(test_name),
      check_encodings(test_name),
      check_verbose(test_name),
      check_warning_flags(test_name),
    ]
    GC.start if leaks.any?
  end

  def check_verbose test_name
    puts "#{test_name}: $VERBOSE == #{$VERBOSE}" unless @old_verbose == $VERBOSE
  end

  def find_fds
    if IO.respond_to?(:console) and (m = IO.method(:console)).arity.nonzero?
      m[:close]
    end
    %w"/proc/self/fd /dev/fd".each do |fd_dir|
      if File.directory?(fd_dir)
        fds = Dir.open(fd_dir) {|d|
          a = d.grep(/\A\d+\z/, &:to_i)
          if d.respond_to? :fileno
            a -= [d.fileno]
          end
          a
        }
        return fds.sort
      end
    end
    []
  end

  def check_fd_leak(test_name)
    leaked = false
    live1 = @fd_info
    live2 = find_fds
    fd_closed = live1 - live2
    if !fd_closed.empty?
      fd_closed.each {|fd|
        puts "Closed file descriptor: #{test_name}: #{fd}"
      }
    end
    fd_leaked = live2 - live1
    if !@@skip && !fd_leaked.empty?
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
      fd_leaked.select! {|fd|
        str = ''.dup
        pos = nil
        if h[fd]
          str << ' :'
          h[fd].map {|io, autoclose, inspect|
            if ENV["LEAK_CHECKER_TRACE_OBJECT_ALLOCATION"]
              pos = "#{ObjectSpace.allocation_sourcefile(io)}:#{ObjectSpace.allocation_sourceline(io)}"
            end
            s = ' ' + inspect
            s << "(not-autoclose)" if !autoclose
            s
          }.sort.each {|s|
            str << s
          }
        else
          begin
            io = IO.for_fd(fd, autoclose: false)
            s = io.stat
          rescue Errno::EBADF
            # something un-stat-able
            next
          else
            next if /darwin/ =~ RUBY_PLATFORM and [0, -1].include?(s.dev)
            str << ' ' << s.inspect
          ensure
            io&.close
          end
        end
        puts "Leaked file descriptor: #{test_name}: #{fd}#{str}"
        puts "  The IO was created at #{pos}" if pos
        true
      }
      unless fd_leaked.empty?
        unless @@try_lsof == false
          @@try_lsof |= system("lsof -p #$$", out: MiniTest::Unit.output)
        end
      end
      h.each {|fd, list|
        next if list.length <= 1
        if 1 < list.count {|io, autoclose, inspect| autoclose }
          str = list.map {|io, autoclose, inspect| " #{inspect}" + (autoclose ? "(autoclose)" : "") }.sort.join
          puts "Multiple autoclose IO objects for a file descriptor in: #{test_name}: #{str}"
        end
      }
    end
    @fd_info = live2
    @@skip = false
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
      tempfiles = ObjectSpace.each_object(Tempfile).find_all {|t|
        t.instance_variable_defined?(:@tmpfile) and t.path
      }
      [count, tempfiles]
    end
  end

  def check_tempfile_leak(test_name)
    return false unless defined? Tempfile
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
      t != Thread.current && t.alive?
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

  def find_env
    ENV.to_h
  end

  def check_env(test_name)
    old_env = @env_info
    new_env = ENV.to_h
    return false if old_env == new_env
    (old_env.keys | new_env.keys).sort.each {|k|
      if old_env.has_key?(k)
        if new_env.has_key?(k)
          if old_env[k] != new_env[k]
            puts "Environment variable changed: #{test_name} : #{k.inspect} changed : #{old_env[k].inspect} -> #{new_env[k].inspect}"
          end
        else
          puts "Environment variable changed: #{test_name} : #{k.inspect} deleted"
        end
      else
        if new_env.has_key?(k)
          puts "Environment variable changed: #{test_name} : #{k.inspect} added"
        else
          flunk "unreachable"
        end
      end
    }
    @env_info = new_env
    return true
  end

  def find_encodings
    {
      'Encoding.default_internal' => Encoding.default_internal,
      'Encoding.default_external' => Encoding.default_external,
      'STDIN.internal_encoding' => STDIN.internal_encoding,
      'STDIN.external_encoding' => STDIN.external_encoding,
      'STDOUT.internal_encoding' => STDOUT.internal_encoding,
      'STDOUT.external_encoding' => STDOUT.external_encoding,
      'STDERR.internal_encoding' => STDERR.internal_encoding,
      'STDERR.external_encoding' => STDERR.external_encoding,
    }
  end

  def check_encodings(test_name)
    old_encoding_info = @encoding_info
    @encoding_info = find_encodings
    leaked = false
    @encoding_info.each do |key, new_encoding|
      old_encoding = old_encoding_info[key]
      if new_encoding != old_encoding
        leaked = true
        puts "#{key} changed: #{test_name} : #{old_encoding.inspect} to #{new_encoding.inspect}"
      end
    end
    leaked
  end

  WARNING_CATEGORIES = (Warning.respond_to?(:[]) ? %i[deprecated experimental] : []).freeze

  def find_warning_flags
    WARNING_CATEGORIES.to_h do |category|
      [category, Warning[category]]
    end
  end

  def check_warning_flags(test_name)
    new_warning_flags = find_warning_flags
    leaked = false
    WARNING_CATEGORIES.each do |category|
      if new_warning_flags[category] != @old_warning_flags[category]
        leaked = true
        puts "Warning[#{category.inspect}] changed: #{test_name} : #{@old_warning_flags[category]} to #{new_warning_flags[category]}"
      end
    end
    return leaked
  end

  def puts(*a)
    output = MiniTest::Unit.output
    if defined?(output.set_encoding)
      output.set_encoding(nil, nil)
    end
    output.puts(*a)
  end

  def self.skip
    @@skip = true
  end
end
