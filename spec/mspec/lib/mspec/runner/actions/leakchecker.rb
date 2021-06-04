# Adapted from ruby's test/lib/leakchecker.rb.
# Ruby's 2-clause BSDL follows.

# Copyright (C) 1993-2013 Yukihiro Matsumoto. All rights reserved.

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.

# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

class LeakError < StandardError
end

class LeakChecker
  attr_reader :leaks

  def initialize
    @fd_info = find_fds
    @tempfile_info = find_tempfiles
    @thread_info = find_threads
    @env_info = find_env
    @argv_info = find_argv
    @globals_info = find_globals
    @encoding_info = find_encodings
  end

  def check(state)
    @state = state
    @leaks = []
    check_fd_leak
    check_tempfile_leak
    check_thread_leak
    check_process_leak
    check_env
    check_argv
    check_globals
    check_encodings
    check_tracepoints
    GC.start unless @leaks.empty?
    @leaks.empty?
  end

  private
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

  def check_fd_leak
    live1 = @fd_info
    if IO.respond_to?(:console) and (m = IO.method(:console)).arity.nonzero?
      m[:close]
    end
    live2 = find_fds
    fd_closed = live1 - live2
    if !fd_closed.empty?
      fd_closed.each {|fd|
        leak "Closed file descriptor: #{fd}"
      }
    end
    fd_leaked = live2 - live1
    if !fd_leaked.empty?
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
        leak "Leaked file descriptor: #{fd}#{str}"
      }
      #system("lsof -p #$$") if !fd_leaked.empty?
      h.each {|fd, list|
        next if list.length <= 1
        if 1 < list.count {|io, autoclose, inspect| autoclose }
          str = list.map {|io, autoclose, inspect| " #{inspect}" + (autoclose ? "(autoclose)" : "") }.sort.join
          leak "Multiple autoclose IO object for a file descriptor:#{str}"
        end
      }
    end
    @fd_info = live2
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

  def find_tempfiles(prev_count = -1)
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

  def check_tempfile_leak
    return false unless defined? Tempfile
    count1, initial_tempfiles = @tempfile_info
    count2, current_tempfiles = find_tempfiles(count1)
    tempfiles_leaked = current_tempfiles - initial_tempfiles
    if !tempfiles_leaked.empty?
      list = tempfiles_leaked.map {|t| t.inspect }.sort
      list.each {|str|
        leak "Leaked tempfile: #{str}"
      }
      tempfiles_leaked.each {|t| t.close! }
    end
    @tempfile_info = [count2, initial_tempfiles]
  end

  def find_threads
    Thread.list.find_all {|t|
      t != Thread.current && t.alive?
    }
  end

  def check_thread_leak
    live1 = @thread_info
    live2 = find_threads
    thread_finished = live1 - live2
    if !thread_finished.empty?
      list = thread_finished.map {|t| t.inspect }.sort
      list.each {|str|
        leak "Finished thread: #{str}"
      }
    end
    thread_leaked = live2 - live1
    if !thread_leaked.empty?
      list = thread_leaked.map {|t| t.inspect }.sort
      list.each {|str|
        leak "Leaked thread: #{str}"
      }
    end
    @thread_info = live2
  end

  def check_process_leak
    subprocesses_leaked = Process.waitall
    subprocesses_leaked.each { |pid, status|
      leak "Leaked subprocess: #{pid}: #{status}"
    }
  end

  def find_env
    ENV.to_h
  end

  def check_env
    old_env = @env_info
    new_env = find_env
    return if old_env == new_env

    (old_env.keys | new_env.keys).sort.each {|k|
      if old_env.has_key?(k)
        if new_env.has_key?(k)
          if old_env[k] != new_env[k]
            leak "Environment variable changed : #{k.inspect} changed : #{old_env[k].inspect} -> #{new_env[k].inspect}"
          end
        else
          leak "Environment variable changed: #{k.inspect} deleted"
        end
      else
        if new_env.has_key?(k)
          leak "Environment variable changed: #{k.inspect} added"
        else
          flunk "unreachable"
        end
      end
    }
    @env_info = new_env
  end

  def find_argv
    ARGV.map { |e| e.dup }
  end

  def check_argv
    old_argv = @argv_info
    new_argv = find_argv
    if new_argv != old_argv
      leak "ARGV changed: #{old_argv.inspect} to #{new_argv.inspect}"
      @argv_info = new_argv
    end
  end

  def find_globals
    { verbose: $VERBOSE, debug: $DEBUG }
  end

  def check_globals
    old_globals = @globals_info
    new_globals = find_globals
    if new_globals != old_globals
      leak "Globals changed: #{old_globals.inspect} to #{new_globals.inspect}"
      @globals_info = new_globals
    end
  end

  def find_encodings
    [Encoding.default_internal, Encoding.default_external]
  end

  def check_encodings
    old_internal, old_external = @encoding_info
    new_internal, new_external = find_encodings
    if new_internal != old_internal
      leak "Encoding.default_internal changed: #{old_internal.inspect} to #{new_internal.inspect}"
    end
    if new_external != old_external
      leak "Encoding.default_external changed: #{old_external.inspect} to #{new_external.inspect}"
    end
    @encoding_info = [new_internal, new_external]
  end

  def check_tracepoints
    ObjectSpace.each_object(TracePoint) do |tp|
      if tp.enabled?
        leak "TracePoint is still enabled: #{tp.inspect}"
      end
    end
  end

  def leak(message)
    if @leaks.empty?
      $stderr.puts "\n"
      $stderr.puts @state.description
    end
    @leaks << message
    $stderr.puts message
  end
end

class LeakCheckerAction
  def register
    MSpec.register :start, self
    MSpec.register :after, self
  end

  def start
    @checker = LeakChecker.new
  end

  def after(state)
    unless @checker.check(state)
      leak_messages = @checker.leaks
      location = state.description
      if state.example
        location = "#{location}\n#{state.example.source_location.join(':')}"
      end
      MSpec.protect(location) do
        raise LeakError, leak_messages.join("\n")
      end
    end
  end
end
