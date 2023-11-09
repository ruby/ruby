# frozen_string_literal: true

#
# = open3.rb: Popen, but with stderr, too
#
# Author:: Yukihiro Matsumoto
# Documentation:: Konrad Meyer
#
# Open3 gives you access to stdin, stdout, and stderr when running other
# programs.
#

#
# Open3 grants you access to stdin, stdout, stderr and a thread to wait for the
# child process when running another program.
# You can specify various attributes, redirections, current directory, etc., of
# the program in the same way as for Process.spawn.
#
# - Open3.popen3 : pipes for stdin, stdout, stderr
# - Open3.popen2 : pipes for stdin, stdout
# - Open3.popen2e : pipes for stdin, merged stdout and stderr
# - Open3.capture3 : give a string for stdin; get strings for stdout, stderr
# - Open3.capture2 : give a string for stdin; get a string for stdout
# - Open3.capture2e : give a string for stdin; get a string for merged stdout and stderr
# - Open3.pipeline_rw : pipes for first stdin and last stdout of a pipeline
# - Open3.pipeline_r : pipe for last stdout of a pipeline
# - Open3.pipeline_w : pipe for first stdin of a pipeline
# - Open3.pipeline_start : run a pipeline without waiting
# - Open3.pipeline : run a pipeline and wait for its completion
#

require 'open3/version'

module Open3

  # :call-seq:
  #   Open3.popen3([env, ] command_line, options = {}) -> [stdin, stdout, stderr, wait_thread]
  #   Open3.popen3([env, ] exe_path, *args, options = {}) -> [stdin, stdout, stderr, wait_thread]
  #   Open3.popen3([env, ] command_line, options = {}) {|stdin, stdout, stderr, wait_thread| ... } -> object
  #   Open3.popen3([env, ] exe_path, *args, options = {}) {|stdin, stdout, stderr, wait_thread| ... } -> object
  #
  # Basically a wrapper for Process.spawn that:
  #
  # - Creates a child process, by calling Process.spawn with the given arguments.
  # - Creates streams +stdin+, +stdout+, and +stderr+,
  #   which are the standard input, standard output, and standard error streams
  #   in the child process.
  # - Creates thread +wait_thread+ that waits for the child process to exit;
  #   the thread has method +pid+, which returns the process ID
  #   of the child process.
  #
  # With no block given, returns the array
  # <tt>[stdin, stdout, stderr, wait_thread]</tt>.
  # The caller should close each of the three returned streams.
  #
  #   stdin, stdout, stderr, wait_thread = Open3.popen3('echo')
  #   # => [#<IO:fd 8>, #<IO:fd 10>, #<IO:fd 12>, #<Process::Waiter:0x00007f58d5428f58 run>]
  #   stdin.close
  #   stdout.close
  #   stderr.close
  #   wait_thread.pid   # => 2210481
  #   wait_thread.value # => #<Process::Status: pid 2210481 exit 0>
  #
  # With a block given, calls the block with the four variables
  # (three streams and the wait thread)
  # and returns the block's return value.
  # The caller need not close the streams:
  #
  #   Open3.popen3('echo') do |stdin, stdout, stderr, wait_thread|
  #     p stdin
  #     p stdout
  #     p stderr
  #     p wait_thread
  #     p wait_thread.pid
  #     p wait_thread.value
  #   end
  #
  # Output:
  #
  #   #<IO:fd 6>
  #   #<IO:fd 7>
  #   #<IO:fd 9>
  #   #<Process::Waiter:0x00007f58d53606e8 sleep>
  #   2211047
  #   #<Process::Status: pid 2211047 exit 0>
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc].
  #
  # Unlike Process.spawn, this method waits for the child process to exit
  # before returning, so the caller need not do so.
  #
  # Argument +options+ is a hash of options for the new process;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # The single required argument is one of the following:
  #
  # - +command_line+ if it is a string,
  #   and if it begins with a shell reserved word or special built-in,
  #   or if it contains one or more metacharacters.
  # - +exe_path+ otherwise.
  #
  # <b>Argument +command_line+</b>
  #
  # \String argument +command_line+ is a command line to be passed to a shell;
  # it must begin with a shell reserved word, begin with a special built-in,
  # or contain meta characters:
  #
  #   Open3.popen3('if true; then echo "Foo"; fi') {|*args| p args } # Shell reserved word.
  #   Open3.popen3('echo') {|*args| p args }                         # Built-in.
  #   Open3.popen3('date > date.tmp') {|*args| p args }              # Contains meta character.
  #
  # Output (similar for each call above):
  #
  #   [#<IO:(closed)>, #<IO:(closed)>, #<IO:(closed)>, #<Process::Waiter:0x00007f58d52f28c8 dead>]
  #
  # The command line may also contain arguments and options for the command:
  #
  #   Open3.popen3('echo "Foo"') { |i, o, e, t| o.gets }
  #   "Foo\n"
  #
  # <b>Argument +exe_path+</b>
  #
  # Argument +exe_path+ is one of the following:
  #
  # - The string path to an executable to be called.
  # - A 2-element array containing the path to an executable
  #   and the string to be used as the name of the executing process.
  #
  # Example:
  #
  #   Open3.popen3('/usr/bin/date') { |i, o, e, t| o.gets }
  #   # => "Wed Sep 27 02:56:44 PM CDT 2023\n"
  #
  # Ruby invokes the executable directly, with no shell and no shell expansion:
  #
  #   Open3.popen3('doesnt_exist') { |i, o, e, t| o.gets } # Raises Errno::ENOENT
  #
  # If one or more +args+ is given, each is an argument or option
  # to be passed to the executable:
  #
  #   Open3.popen3('echo', 'C #') { |i, o, e, t| o.gets }
  #   # => "C #\n"
  #   Open3.popen3('echo', 'hello', 'world') { |i, o, e, t| o.gets }
  #   # => "hello world\n"
  #
  # Take care to avoid deadlocks.
  # Output streams +stdout+ and +stderr+ have fixed-size buffers,
  # so reading extensively from one but not the other can cause a deadlock
  # when the unread buffer fills.
  # To avoid that, +stdout+ and +stderr+ should be read simultaneously
  # (using threads or IO.select).
  #
  # Related:
  #
  # - Open3.popen2: Makes the standard input and standard output streams
  #   of the child process available as separate streams,
  #   with no access to the standard error stream.
  # - Open3.popen2e: Makes the standard input and the merge
  #   of the standard output and standard error streams
  #   of the child process available as separate streams.
  #
  def popen3(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    err_r, err_w = IO.pipe
    opts[:err] = err_w

    popen_run(cmd, opts, [in_r, out_w, err_w], [in_w, out_r, err_r], &block)
  end
  module_function :popen3

  # :call-seq:
  #   Open3.popen2([env, ] command_line, options = {}) -> [stdin, stdout, wait_thread]
  #   Open3.popen2([env, ] exe_path, *args, options = {}) -> [stdin, stdout, wait_thread]
  #   Open3.popen2([env, ] command_line, options = {}) {|stdin, stdout, wait_thread| ... } -> object
  #   Open3.popen2([env, ] exe_path, *args, options = {}) {|stdin, stdout, wait_thread| ... } -> object
  #
  # Basically a wrapper for Process.spawn that:
  #
  # - Creates a child process, by calling Process.spawn with the given arguments.
  # - Creates streams +stdin+ and +stdout+,
  #   which are the standard input and standard output streams
  #   in the child process.
  # - Creates thread +wait_thread+ that waits for the child process to exit;
  #   the thread has method +pid+, which returns the process ID
  #   of the child process.
  #
  # With no block given, returns the array
  # <tt>[stdin, stdout, wait_thread]</tt>.
  # The caller should close each of the two returned streams.
  #
  #   stdin, stdout, wait_thread = Open3.popen2('echo')
  #   # => [#<IO:fd 6>, #<IO:fd 7>, #<Process::Waiter:0x00007f58d52dbe98 run>]
  #   stdin.close
  #   stdout.close
  #   wait_thread.pid   # => 2263572
  #   wait_thread.value # => #<Process::Status: pid 2263572 exit 0>
  #
  # With a block given, calls the block with the three variables
  # (two streams and the wait thread)
  # and returns the block's return value.
  # The caller need not close the streams:
  #
  #   Open3.popen2('echo') do |stdin, stdout, wait_thread|
  #     p stdin
  #     p stdout
  #     p wait_thread
  #     p wait_thread.pid
  #     p wait_thread.value
  #   end
  #
  # Output:
  #
  #   #<IO:fd 6>
  #   #<IO:fd 7>
  #   #<Process::Waiter:0x00007f58d59a34b0 sleep>
  #   2263636
  #   #<Process::Status: pid 2263636 exit 0>
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc].
  #
  # Unlike Process.spawn, this method waits for the child process to exit
  # before returning, so the caller need not do so.
  #
  # Argument +options+ is a hash of options for the new process;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # The single required argument is one of the following:
  #
  # - +command_line+ if it is a string,
  #   and if it begins with a shell reserved word or special built-in,
  #   or if it contains one or more metacharacters.
  # - +exe_path+ otherwise.
  #
  # <b>Argument +command_line+</b>
  #
  # \String argument +command_line+ is a command line to be passed to a shell;
  # it must begin with a shell reserved word, begin with a special built-in,
  # or contain meta characters:
  #
  #   Open3.popen2('if true; then echo "Foo"; fi') {|*args| p args } # Shell reserved word.
  #   Open3.popen2('echo') {|*args| p args }                         # Built-in.
  #   Open3.popen2('date > date.tmp') {|*args| p args }              # Contains meta character.
  #
  # Output (similar for each call above):
  #
  #   # => [#<IO:(closed)>, #<IO:(closed)>, #<Process::Waiter:0x00007f7577dfe410 dead>]
  #
  # The command line may also contain arguments and options for the command:
  #
  #   Open3.popen2('echo "Foo"') { |i, o, t| o.gets }
  #   "Foo\n"
  #
  # <b>Argument +exe_path+</b>
  #
  # Argument +exe_path+ is one of the following:
  #
  # - The string path to an executable to be called.
  # - A 2-element array containing the path to an executable
  #   and the string to be used as the name of the executing process.
  #
  # Example:
  #
  #   Open3.popen2('/usr/bin/date') { |i, o, t| o.gets }
  #   # => "Thu Sep 28 09:41:06 AM CDT 2023\n"
  #
  # Ruby invokes the executable directly, with no shell and no shell expansion:
  #
  #   Open3.popen2('doesnt_exist') { |i, o, t| o.gets } # Raises Errno::ENOENT
  #
  # If one or more +args+ is given, each is an argument or option
  # to be passed to the executable:
  #
  #   Open3.popen2('echo', 'C #') { |i, o, t| o.gets }
  #   # => "C #\n"
  #   Open3.popen2('echo', 'hello', 'world') { |i, o, t| o.gets }
  #   # => "hello world\n"
  #
  #
  # Related:
  #
  # - Open3.popen2e: Makes the standard input and the merge
  #   of the standard output and standard error streams
  #   of the child process available as separate streams.
  # - Open3.popen3: Makes the standard input, standard output,
  #   and standard error streams
  #   of the child process available as separate streams.
  #
  def popen2(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    popen_run(cmd, opts, [in_r, out_w], [in_w, out_r], &block)
  end
  module_function :popen2

  # :call-seq:
  #   Open3.popen2e([env, ] command_line, options = {}) -> [stdin, stdout_and_stderr, wait_thread]
  #   Open3.popen2e([env, ] exe_path, *args, options = {}) -> [stdin, stdout_and_stderr, wait_thread]
  #   Open3.popen2e([env, ] command_line, options = {}) {|stdin, stdout_and_stderr, wait_thread| ... } -> object
  #   Open3.popen2e([env, ] exe_path, *args, options = {}) {|stdin, stdout_and_stderr, wait_thread| ... } -> object
  #
  # Basically a wrapper for Process.spawn that:
  #
  # - Creates a child process, by calling Process.spawn with the given arguments.
  # - Creates streams +stdin+, +stdout_and_stderr+,
  #   which are the standard input and the merge of the standard output
  #   and standard error streams in the child process.
  # - Creates thread +wait_thread+ that waits for the child process to exit;
  #   the thread has method +pid+, which returns the process ID
  #   of the child process.
  #
  # With no block given, returns the array
  # <tt>[stdin, stdout_and_stderr, wait_thread]</tt>.
  # The caller should close each of the two returned streams.
  #
  #   stdin, stdout_and_stderr, wait_thread = Open3.popen2e('echo')
  #   # => [#<IO:fd 6>, #<IO:fd 7>, #<Process::Waiter:0x00007f7577da4398 run>]
  #   stdin.close
  #   stdout_and_stderr.close
  #   wait_thread.pid   # => 2274600
  #   wait_thread.value # => #<Process::Status: pid 2274600 exit 0>
  #
  # With a block given, calls the block with the three variables
  # (two streams and the wait thread)
  # and returns the block's return value.
  # The caller need not close the streams:
  #
  #   Open3.popen2e('echo') do |stdin, stdout_and_stderr, wait_thread|
  #     p stdin
  #     p stdout_and_stderr
  #     p wait_thread
  #     p wait_thread.pid
  #     p wait_thread.value
  #   end
  #
  # Output:
  #
  #   #<IO:fd 6>
  #   #<IO:fd 7>
  #   #<Process::Waiter:0x00007f75777578c8 sleep>
  #   2274763
  #   #<Process::Status: pid 2274763 exit 0>
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc].
  #
  # Unlike Process.spawn, this method waits for the child process to exit
  # before returning, so the caller need not do so.
  #
  # Argument +options+ is a hash of options for the new process;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # The single required argument is one of the following:
  #
  # - +command_line+ if it is a string,
  #   and if it begins with a shell reserved word or special built-in,
  #   or if it contains one or more metacharacters.
  # - +exe_path+ otherwise.
  #
  # <b>Argument +command_line+</b>
  #
  # \String argument +command_line+ is a command line to be passed to a shell;
  # it must begin with a shell reserved word, begin with a special built-in,
  # or contain meta characters:
  #
  #   Open3.popen2e('if true; then echo "Foo"; fi') {|*args| p args } # Shell reserved word.
  #   Open3.popen2e('echo') {|*args| p args }                         # Built-in.
  #   Open3.popen2e('date > date.tmp') {|*args| p args }              # Contains meta character.
  #
  # Output (similar for each call above):
  #
  #   # => [#<IO:(closed)>, #<IO:(closed)>, #<Process::Waiter:0x00007f7577d8a1f0 dead>]
  #
  # The command line may also contain arguments and options for the command:
  #
  #   Open3.popen2e('echo "Foo"') { |i, o_and_e, t| o_and_e.gets }
  #   "Foo\n"
  #
  # <b>Argument +exe_path+</b>
  #
  # Argument +exe_path+ is one of the following:
  #
  # - The string path to an executable to be called.
  # - A 2-element array containing the path to an executable
  #   and the string to be used as the name of the executing process.
  #
  # Example:
  #
  #   Open3.popen2e('/usr/bin/date') { |i, o_and_e, t| o_and_e.gets }
  #   # => "Thu Sep 28 01:58:45 PM CDT 2023\n"
  #
  # Ruby invokes the executable directly, with no shell and no shell expansion:
  #
  #   Open3.popen2e('doesnt_exist') { |i, o_and_e, t| o_and_e.gets } # Raises Errno::ENOENT
  #
  # If one or more +args+ is given, each is an argument or option
  # to be passed to the executable:
  #
  #   Open3.popen2e('echo', 'C #') { |i, o_and_e, t| o_and_e.gets }
  #   # => "C #\n"
  #   Open3.popen2e('echo', 'hello', 'world') { |i, o_and_e, t| o_and_e.gets }
  #   # => "hello world\n"
  #
  # Related:
  #
  # - Open3.popen2: Makes the standard input and standard output streams
  #   of the child process available as separate streams,
  #   with no access to the standard error stream.
  # - Open3.popen3: Makes the standard input, standard output,
  #   and standard error streams
  #   of the child process available as separate streams.
  #
  def popen2e(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[[:out, :err]] = out_w

    popen_run(cmd, opts, [in_r, out_w], [in_w, out_r], &block)
  ensure
    if block
      in_r.close
      in_w.close
      out_r.close
      out_w.close
    end
  end
  module_function :popen2e

  def popen_run(cmd, opts, child_io, parent_io) # :nodoc:
    pid = spawn(*cmd, opts)
    wait_thr = Process.detach(pid)
    child_io.each(&:close)
    result = [*parent_io, wait_thr]
    if defined? yield
      begin
        return yield(*result)
      ensure
        parent_io.each(&:close)
        wait_thr.join
      end
    end
    result
  end
  module_function :popen_run
  class << self
    private :popen_run
  end

  # :call-seq:
  #   Open3.capture3([env, ] command_line, options = {}) -> [stdout_s, stderr_s, status]
  #   Open3.capture3([env, ] exe_path, *args, options = {}) -> [stdout_s, stderr_s, status]
  #
  # Basically a wrapper for Open3.popen3 that:
  #
  # - Creates a child process, by calling Open3.popen3 with the given arguments
  #   (except for certain entries in hash +options+; see below).
  # - Returns as strings +stdout_s+ and +stderr_s+ the standard output
  #   and standard error of the child process.
  # - Returns as +status+ a <tt>Process::Status</tt> object
  #   that represents the exit status of the child process.
  #
  # Returns the array <tt>[stdout_s, stderr_s, status]</tt>:
  #
  #   stdout_s, stderr_s, status = Open3.capture3('echo "Foo"')
  #   # => ["Foo\n", "", #<Process::Status: pid 2281954 exit 0>]
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc].
  #
  # Unlike Process.spawn, this method waits for the child process to exit
  # before returning, so the caller need not do so.
  #
  # Argument +options+ is a hash of options for the new process;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # The hash +options+ is passed to method Open3.popen3;
  # two options have local effect in method Open3.capture3:
  #
  # - If entry <tt>options[:stdin_data]</tt> exists, the entry is removed
  #   and its string value is sent to the command's standard input:
  #
  #     Open3.capture3('tee', stdin_data: 'Foo')
  #     # => ["Foo", "", #<Process::Status: pid 2319575 exit 0>]
  #
  # - If entry <tt>options[:binmode]</tt> exists, the entry is removed
  #   the internal streams are set to binary mode.
  #
  # The single required argument is one of the following:
  #
  # - +command_line+ if it is a string,
  #   and if it begins with a shell reserved word or special built-in,
  #   or if it contains one or more metacharacters.
  # - +exe_path+ otherwise.
  #
  # <b>Argument +command_line+</b>
  #
  # \String argument +command_line+ is a command line to be passed to a shell;
  # it must begin with a shell reserved word, begin with a special built-in,
  # or contain meta characters:
  #
  #   Open3.capture3('if true; then echo "Foo"; fi') # Shell reserved word.
  #   # => ["Foo\n", "", #<Process::Status: pid 2282025 exit 0>]
  #   Open3.capture3('echo')                         # Built-in.
  #   # => ["\n", "", #<Process::Status: pid 2282092 exit 0>]
  #   Open3.capture3('date > date.tmp')              # Contains meta character.
  #   # => ["", "", #<Process::Status: pid 2282110 exit 0>]
  #
  # The command line may also contain arguments and options for the command:
  #
  #   Open3.capture3('echo "Foo"')
  #   # => ["Foo\n", "", #<Process::Status: pid 2282092 exit 0>]
  #
  # <b>Argument +exe_path+</b>
  #
  # Argument +exe_path+ is one of the following:
  #
  # - The string path to an executable to be called.
  # - A 2-element array containing the path to an executable
  #   and the string to be used as the name of the executing process.
  #
  # Example:
  #
  #   Open3.capture3('/usr/bin/date')
  #   # => ["Thu Sep 28 05:03:51 PM CDT 2023\n", "", #<Process::Status: pid 2282300 exit 0>]
  #
  # Ruby invokes the executable directly, with no shell and no shell expansion:
  #
  #   Open3.capture3('doesnt_exist') # Raises Errno::ENOENT
  #
  # If one or more +args+ is given, each is an argument or option
  # to be passed to the executable:
  #
  #   Open3.capture3('echo', 'C #')
  #   # => ["C #\n", "", #<Process::Status: pid 2282368 exit 0>]
  #   Open3.capture3('echo', 'hello', 'world')
  #   # => ["hello world\n", "", #<Process::Status: pid 2282372 exit 0>]
  #
  def capture3(*cmd)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    stdin_data = opts.delete(:stdin_data) || ''
    binmode = opts.delete(:binmode)

    popen3(*cmd, opts) {|i, o, e, t|
      if binmode
        i.binmode
        o.binmode
        e.binmode
      end
      out_reader = Thread.new { o.read }
      err_reader = Thread.new { e.read }
      begin
        if stdin_data.respond_to? :readpartial
          IO.copy_stream(stdin_data, i)
        else
          i.write stdin_data
        end
      rescue Errno::EPIPE
      end
      i.close
      [out_reader.value, err_reader.value, t.value]
    }
  end
  module_function :capture3

  # :call-seq:
  #   Open3.capture2([env, ] command_line, options = {}) -> [stdout_s, status]
  #   Open3.capture2([env, ] exe_path, *args, options = {}) -> [stdout_s, status]
  #
  # Basically a wrapper for Open3.popen3 that:
  #
  # - Creates a child process, by calling Open3.popen3 with the given arguments
  #   (except for certain entries in hash +options+; see below).
  # - Returns as string +stdout_s+ the standard output of the child process.
  # - Returns as +status+ a <tt>Process::Status</tt> object
  #   that represents the exit status of the child process.
  #
  # Returns the array <tt>[stdout_s, status]</tt>:
  #
  #   stdout_s, status = Open3.capture2('echo "Foo"')
  #   # => ["Foo\n", #<Process::Status: pid 2326047 exit 0>]
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc].
  #
  # Unlike Process.spawn, this method waits for the child process to exit
  # before returning, so the caller need not do so.
  #
  # Argument +options+ is a hash of options for the new process;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # The hash +options+ is passed to method Open3.popen3;
  # two options have local effect in method Open3.capture2:
  #
  # - If entry <tt>options[:stdin_data]</tt> exists, the entry is removed
  #   and its string value is sent to the command's standard input:
  #
  #     Open3.capture2('tee', stdin_data: 'Foo')
  #
  #     # => ["Foo", #<Process::Status: pid 2326087 exit 0>]
  #
  #   the internal streams are set to binary mode.
  #
  # The single required argument is one of the following:
  #
  # - +command_line+ if it is a string,
  #   and if it begins with a shell reserved word or special built-in,
  #   or if it contains one or more metacharacters.
  # - +exe_path+ otherwise.
  #
  # <b>Argument +command_line+</b>
  #
  # \String argument +command_line+ is a command line to be passed to a shell;
  # it must begin with a shell reserved word, begin with a special built-in,
  # or contain meta characters:
  #
  #   Open3.capture2('if true; then echo "Foo"; fi') # Shell reserved word.
  #   # => ["Foo\n", #<Process::Status: pid 2326131 exit 0>]
  #   Open3.capture2('echo')                         # Built-in.
  #   # => ["\n", #<Process::Status: pid 2326139 exit 0>]
  #   Open3.capture2('date > date.tmp')              # Contains meta character.
  #   # => ["", #<Process::Status: pid 2326174 exit 0>]
  #
  # The command line may also contain arguments and options for the command:
  #
  #   Open3.capture2('echo "Foo"')
  #   # => ["Foo\n", #<Process::Status: pid 2326183 exit 0>]
  #
  # <b>Argument +exe_path+</b>
  #
  # Argument +exe_path+ is one of the following:
  #
  # - The string path to an executable to be called.
  # - A 2-element array containing the path to an executable
  #   and the string to be used as the name of the executing process.
  #
  # Example:
  #
  #   Open3.capture2('/usr/bin/date')
  #   # => ["Fri Sep 29 01:00:39 PM CDT 2023\n", #<Process::Status: pid 2326222 exit 0>]
  #
  # Ruby invokes the executable directly, with no shell and no shell expansion:
  #
  #   Open3.capture2('doesnt_exist') # Raises Errno::ENOENT
  #
  # If one or more +args+ is given, each is an argument or option
  # to be passed to the executable:
  #
  #   Open3.capture2('echo', 'C #')
  #   # => ["C #\n", #<Process::Status: pid 2326267 exit 0>]
  #   Open3.capture2('echo', 'hello', 'world')
  #   # => ["hello world\n", #<Process::Status: pid 2326299 exit 0>]
  #
  def capture2(*cmd)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    stdin_data = opts.delete(:stdin_data)
    binmode = opts.delete(:binmode)

    popen2(*cmd, opts) {|i, o, t|
      if binmode
        i.binmode
        o.binmode
      end
      out_reader = Thread.new { o.read }
      if stdin_data
        begin
          if stdin_data.respond_to? :readpartial
            IO.copy_stream(stdin_data, i)
          else
            i.write stdin_data
          end
        rescue Errno::EPIPE
        end
      end
      i.close
      [out_reader.value, t.value]
    }
  end
  module_function :capture2

  # :call-seq:
  #   Open3.capture2e([env, ] command_line, options = {}) -> [stdout_and_stderr_s, status]
  #   Open3.capture2e([env, ] exe_path, *args, options = {}) -> [stdout_and_stderr_s, status]
  #
  # Basically a wrapper for Open3.popen3 that:
  #
  # - Creates a child process, by calling Open3.popen3 with the given arguments
  #   (except for certain entries in hash +options+; see below).
  # - Returns as string +stdout_and_stderr_s+ the merged standard output
  #   and standard error of the child process.
  # - Returns as +status+ a <tt>Process::Status</tt> object
  #   that represents the exit status of the child process.
  #
  # Returns the array <tt>[stdout_and_stderr_s, status]</tt>:
  #
  #   stdout_and_stderr_s, status = Open3.capture2e('echo "Foo"')
  #   # => ["Foo\n", #<Process::Status: pid 2371692 exit 0>]
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc].
  #
  # Unlike Process.spawn, this method waits for the child process to exit
  # before returning, so the caller need not do so.
  #
  # Argument +options+ is a hash of options for the new process;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # The hash +options+ is passed to method Open3.popen3;
  # two options have local effect in method Open3.capture2e:
  #
  # - If entry <tt>options[:stdin_data]</tt> exists, the entry is removed
  #   and its string value is sent to the command's standard input:
  #
  #     Open3.capture2e('tee', stdin_data: 'Foo')
  #     # => ["Foo", #<Process::Status: pid 2371732 exit 0>]
  #
  #   the internal streams are set to binary mode.
  #
  # The single required argument is one of the following:
  #
  # - +command_line+ if it is a string,
  #   and if it begins with a shell reserved word or special built-in,
  #   or if it contains one or more metacharacters.
  # - +exe_path+ otherwise.
  #
  # <b>Argument +command_line+</b>
  #
  # \String argument +command_line+ is a command line to be passed to a shell;
  # it must begin with a shell reserved word, begin with a special built-in,
  # or contain meta characters:
  #
  #   Open3.capture2e('if true; then echo "Foo"; fi') # Shell reserved word.
  #   # => ["Foo\n", #<Process::Status: pid 2371740 exit 0>]
  #   Open3.capture2e('echo')                         # Built-in.
  #   # => ["\n", #<Process::Status: pid 2371774 exit 0>]
  #   Open3.capture2e('date > date.tmp')              # Contains meta character.
  #   # => ["", #<Process::Status: pid 2371812 exit 0>]
  #
  # The command line may also contain arguments and options for the command:
  #
  #   Open3.capture2e('echo "Foo"')
  #   # => ["Foo\n", #<Process::Status: pid 2326183 exit 0>]
  #
  # <b>Argument +exe_path+</b>
  #
  # Argument +exe_path+ is one of the following:
  #
  # - The string path to an executable to be called.
  # - A 2-element array containing the path to an executable
  #   and the string to be used as the name of the executing process.
  #
  # Example:
  #
  #   Open3.capture2e('/usr/bin/date')
  #   # => ["Sat Sep 30 09:01:46 AM CDT 2023\n", #<Process::Status: pid 2371820 exit 0>]
  #
  # Ruby invokes the executable directly, with no shell and no shell expansion:
  #
  #   Open3.capture2e('doesnt_exist') # Raises Errno::ENOENT
  #
  # If one or more +args+ is given, each is an argument or option
  # to be passed to the executable:
  #
  #   Open3.capture2e('echo', 'C #')
  #   # => ["C #\n", #<Process::Status: pid 2371856 exit 0>]
  #   Open3.capture2e('echo', 'hello', 'world')
  #   # => ["hello world\n", #<Process::Status: pid 2371894 exit 0>]
  #
  def capture2e(*cmd)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    stdin_data = opts.delete(:stdin_data)
    binmode = opts.delete(:binmode)

    popen2e(*cmd, opts) {|i, oe, t|
      if binmode
        i.binmode
        oe.binmode
      end
      outerr_reader = Thread.new { oe.read }
      if stdin_data
        begin
          if stdin_data.respond_to? :readpartial
            IO.copy_stream(stdin_data, i)
          else
            i.write stdin_data
          end
        rescue Errno::EPIPE
        end
      end
      i.close
      [outerr_reader.value, t.value]
    }
  end
  module_function :capture2e

  # Open3.pipeline_rw starts a list of commands as a pipeline with pipes
  # which connect to stdin of the first command and stdout of the last command.
  #
  #   Open3.pipeline_rw(cmd1, cmd2, ... [, opts]) {|first_stdin, last_stdout, wait_threads|
  #     ...
  #   }
  #
  #   first_stdin, last_stdout, wait_threads = Open3.pipeline_rw(cmd1, cmd2, ... [, opts])
  #   ...
  #   first_stdin.close
  #   last_stdout.close
  #
  # Each cmd is a string or an array.
  # If it is an array, the elements are passed to Process.spawn.
  #
  #   cmd:
  #     commandline                              command line string which is passed to a shell
  #     [env, commandline, opts]                 command line string which is passed to a shell
  #     [env, cmdname, arg1, ..., opts]          command name and one or more arguments (no shell)
  #     [env, [cmdname, argv0], arg1, ..., opts] command name and arguments including argv[0] (no shell)
  #
  #   Note that env and opts are optional, as for Process.spawn.
  #
  # The options to pass to Process.spawn are constructed by merging
  # +opts+, the last hash element of the array, and
  # specifications for the pipes between each of the commands.
  #
  # Example:
  #
  #   Open3.pipeline_rw("tr -dc A-Za-z", "wc -c") {|i, o, ts|
  #     i.puts "All persons more than a mile high to leave the court."
  #     i.close
  #     p o.gets #=> "42\n"
  #   }
  #
  #   Open3.pipeline_rw("sort", "cat -n") {|stdin, stdout, wait_thrs|
  #     stdin.puts "foo"
  #     stdin.puts "bar"
  #     stdin.puts "baz"
  #     stdin.close     # send EOF to sort.
  #     p stdout.read   #=> "     1\tbar\n     2\tbaz\n     3\tfoo\n"
  #   }
  def pipeline_rw(*cmds, &block)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    pipeline_run(cmds, opts, [in_r, out_w], [in_w, out_r], &block)
  end
  module_function :pipeline_rw

  # Open3.pipeline_r starts a list of commands as a pipeline with a pipe
  # which connects to stdout of the last command.
  #
  #   Open3.pipeline_r(cmd1, cmd2, ... [, opts]) {|last_stdout, wait_threads|
  #     ...
  #   }
  #
  #   last_stdout, wait_threads = Open3.pipeline_r(cmd1, cmd2, ... [, opts])
  #   ...
  #   last_stdout.close
  #
  # Each cmd is a string or an array.
  # If it is an array, the elements are passed to Process.spawn.
  #
  #   cmd:
  #     commandline                              command line string which is passed to a shell
  #     [env, commandline, opts]                 command line string which is passed to a shell
  #     [env, cmdname, arg1, ..., opts]          command name and one or more arguments (no shell)
  #     [env, [cmdname, argv0], arg1, ..., opts] command name and arguments including argv[0] (no shell)
  #
  #   Note that env and opts are optional, as for Process.spawn.
  #
  # Example:
  #
  #   Open3.pipeline_r("zcat /var/log/apache2/access.log.*.gz",
  #                    [{"LANG"=>"C"}, "grep", "GET /favicon.ico"],
  #                    "logresolve") {|o, ts|
  #     o.each_line {|line|
  #       ...
  #     }
  #   }
  #
  #   Open3.pipeline_r("yes", "head -10") {|o, ts|
  #     p o.read      #=> "y\ny\ny\ny\ny\ny\ny\ny\ny\ny\n"
  #     p ts[0].value #=> #<Process::Status: pid 24910 SIGPIPE (signal 13)>
  #     p ts[1].value #=> #<Process::Status: pid 24913 exit 0>
  #   }
  #
  def pipeline_r(*cmds, &block)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    pipeline_run(cmds, opts, [out_w], [out_r], &block)
  end
  module_function :pipeline_r

  # Open3.pipeline_w starts a list of commands as a pipeline with a pipe
  # which connects to stdin of the first command.
  #
  #   Open3.pipeline_w(cmd1, cmd2, ... [, opts]) {|first_stdin, wait_threads|
  #     ...
  #   }
  #
  #   first_stdin, wait_threads = Open3.pipeline_w(cmd1, cmd2, ... [, opts])
  #   ...
  #   first_stdin.close
  #
  # Each cmd is a string or an array.
  # If it is an array, the elements are passed to Process.spawn.
  #
  #   cmd:
  #     commandline                              command line string which is passed to a shell
  #     [env, commandline, opts]                 command line string which is passed to a shell
  #     [env, cmdname, arg1, ..., opts]          command name and one or more arguments (no shell)
  #     [env, [cmdname, argv0], arg1, ..., opts] command name and arguments including argv[0] (no shell)
  #
  #   Note that env and opts are optional, as for Process.spawn.
  #
  # Example:
  #
  #   Open3.pipeline_w("bzip2 -c", :out=>"/tmp/hello.bz2") {|i, ts|
  #     i.puts "hello"
  #   }
  #
  def pipeline_w(*cmds, &block)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    pipeline_run(cmds, opts, [in_r], [in_w], &block)
  end
  module_function :pipeline_w

  # Open3.pipeline_start starts a list of commands as a pipeline.
  # No pipes are created for stdin of the first command and
  # stdout of the last command.
  #
  #   Open3.pipeline_start(cmd1, cmd2, ... [, opts]) {|wait_threads|
  #     ...
  #   }
  #
  #   wait_threads = Open3.pipeline_start(cmd1, cmd2, ... [, opts])
  #   ...
  #
  # Each cmd is a string or an array.
  # If it is an array, the elements are passed to Process.spawn.
  #
  #   cmd:
  #     commandline                              command line string which is passed to a shell
  #     [env, commandline, opts]                 command line string which is passed to a shell
  #     [env, cmdname, arg1, ..., opts]          command name and one or more arguments (no shell)
  #     [env, [cmdname, argv0], arg1, ..., opts] command name and arguments including argv[0] (no shell)
  #
  #   Note that env and opts are optional, as for Process.spawn.
  #
  # Example:
  #
  #   # Run xeyes in 10 seconds.
  #   Open3.pipeline_start("xeyes") {|ts|
  #     sleep 10
  #     t = ts[0]
  #     Process.kill("TERM", t.pid)
  #     p t.value #=> #<Process::Status: pid 911 SIGTERM (signal 15)>
  #   }
  #
  #   # Convert pdf to ps and send it to a printer.
  #   # Collect error message of pdftops and lpr.
  #   pdf_file = "paper.pdf"
  #   printer = "printer-name"
  #   err_r, err_w = IO.pipe
  #   Open3.pipeline_start(["pdftops", pdf_file, "-"],
  #                        ["lpr", "-P#{printer}"],
  #                        :err=>err_w) {|ts|
  #     err_w.close
  #     p err_r.read # error messages of pdftops and lpr.
  #   }
  #
  def pipeline_start(*cmds, &block)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    if block
      pipeline_run(cmds, opts, [], [], &block)
    else
      ts, = pipeline_run(cmds, opts, [], [])
      ts
    end
  end
  module_function :pipeline_start

  # Open3.pipeline starts a list of commands as a pipeline.
  # It waits for the completion of the commands.
  # No pipes are created for stdin of the first command and
  # stdout of the last command.
  #
  #   status_list = Open3.pipeline(cmd1, cmd2, ... [, opts])
  #
  # Each cmd is a string or an array.
  # If it is an array, the elements are passed to Process.spawn.
  #
  #   cmd:
  #     commandline                              command line string which is passed to a shell
  #     [env, commandline, opts]                 command line string which is passed to a shell
  #     [env, cmdname, arg1, ..., opts]          command name and one or more arguments (no shell)
  #     [env, [cmdname, argv0], arg1, ..., opts] command name and arguments including argv[0] (no shell)
  #
  #   Note that env and opts are optional, as Process.spawn.
  #
  # Example:
  #
  #   fname = "/usr/share/man/man1/ruby.1.gz"
  #   p Open3.pipeline(["zcat", fname], "nroff -man", "less")
  #   #=> [#<Process::Status: pid 11817 exit 0>,
  #   #    #<Process::Status: pid 11820 exit 0>,
  #   #    #<Process::Status: pid 11828 exit 0>]
  #
  #   fname = "/usr/share/man/man1/ls.1.gz"
  #   Open3.pipeline(["zcat", fname], "nroff -man", "colcrt")
  #
  #   # convert PDF to PS and send to a printer by lpr
  #   pdf_file = "paper.pdf"
  #   printer = "printer-name"
  #   Open3.pipeline(["pdftops", pdf_file, "-"],
  #                  ["lpr", "-P#{printer}"])
  #
  #   # count lines
  #   Open3.pipeline("sort", "uniq -c", :in=>"names.txt", :out=>"count")
  #
  #   # cyclic pipeline
  #   r,w = IO.pipe
  #   w.print "ibase=14\n10\n"
  #   Open3.pipeline("bc", "tee /dev/tty", :in=>r, :out=>w)
  #   #=> 14
  #   #   18
  #   #   22
  #   #   30
  #   #   42
  #   #   58
  #   #   78
  #   #   106
  #   #   202
  #
  def pipeline(*cmds)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    pipeline_run(cmds, opts, [], []) {|ts|
      ts.map(&:value)
    }
  end
  module_function :pipeline

  def pipeline_run(cmds, pipeline_opts, child_io, parent_io) # :nodoc:
    if cmds.empty?
      raise ArgumentError, "no commands"
    end

    opts_base = pipeline_opts.dup
    opts_base.delete :in
    opts_base.delete :out

    wait_thrs = []
    r = nil
    cmds.each_with_index {|cmd, i|
      cmd_opts = opts_base.dup
      if String === cmd
        cmd = [cmd]
      else
        cmd_opts.update cmd.pop if Hash === cmd.last
      end
      if i == 0
        if !cmd_opts.include?(:in)
          if pipeline_opts.include?(:in)
            cmd_opts[:in] = pipeline_opts[:in]
          end
        end
      else
        cmd_opts[:in] = r
      end
      if i != cmds.length - 1
        r2, w2 = IO.pipe
        cmd_opts[:out] = w2
      else
        if !cmd_opts.include?(:out)
          if pipeline_opts.include?(:out)
            cmd_opts[:out] = pipeline_opts[:out]
          end
        end
      end
      pid = spawn(*cmd, cmd_opts)
      wait_thrs << Process.detach(pid)
      r&.close
      w2&.close
      r = r2
    }
    result = parent_io + [wait_thrs]
    child_io.each(&:close)
    if defined? yield
      begin
        return yield(*result)
      ensure
        parent_io.each(&:close)
        wait_thrs.each(&:join)
      end
    end
    result
  end
  module_function :pipeline_run
  class << self
    private :pipeline_run
  end

end

# JRuby uses different popen logic on Windows, require it here to reuse wrapper methods above.
require 'open3/jruby_windows' if RUBY_ENGINE == 'jruby' && JRuby::Util::ON_WINDOWS
