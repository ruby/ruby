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
# Open3 grants you access to stdin, stdout, stderr and a thread to wait the
# child process when running another program.
#
# Example:
#
#   require "open3"
#   include Open3
#   
#   stdin, stdout, stderr, wait_thr = popen3('nroff -man')
#
# Open3.popen3 can also take a block which will receive stdin, stdout,
# stderr and wait_thr as parameters.
# This ensures stdin, stdout and stderr are closed and
# the process is terminated once the block exits.
#
# Example:
#
#   require "open3"
#
#   Open3.popen3('nroff -man') { |stdin, stdout, stderr, wait_thr| ... }
#

module Open3

  # Open stdin, stdout, and stderr streams and start external executable.
  # In addition, a thread for waiting the started process is noticed.
  # The thread has a pid method and thread variable :pid which is the pid of
  # the started process.
  #
  # Block form:
  #
  #   Open3.popen3(cmd... [, opts]) {|stdin, stdout, stderr, wait_thr|
  #     pid = wait_thr.pid # pid of the started process.
  #     ...
  #     exit_status = wait_thr.value # Process::Status object returned.
  #   }
  #
  # Non-block form:
  #   
  #   stdin, stdout, stderr, wait_thr = Open3.popen3(cmd... [, opts])
  #   pid = wait_thr[:pid]  # pid of the started process.
  #   ...
  #   stdin.close  # stdin, stdout and stderr should be closed explicitly in this form.
  #   stdout.close
  #   stderr.close
  #   exit_status = wait_thr.value  # Process::Status object returned.
  #
  # The parameters +cmd...+ is passed to Kernel#spawn.
  # So a commandline string and list of argument strings can be accepted as follows.
  #
  #   Open3.popen3("echo a") {|i, o, e, t| ... }
  #   Open3.popen3("echo", "a") {|i, o, e, t| ... }
  #   Open3.popen3(["echo", "argv0"], "a") {|i, o, e, t| ... }
  #
  # If the last parameter, opts, is a Hash, it is recognized as an option for Kernel#spawn.
  #
  #   Open3.popen3("pwd", :chdir=>"/") {|i,o,e,t|
  #     p o.read.chomp #=> "/"
  #   }
  #
  # wait_thr.value waits the termination of the process.
  # The block form also waits the process when it returns.
  #
  # Closing stdin, stdout and stderr does not wait the process.
  #
  def popen3(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[STDIN] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[STDOUT] = out_w

    err_r, err_w = IO.pipe
    opts[STDERR] = err_w

    popen_run(cmd, opts, [in_r, out_w, err_w], [in_w, out_r, err_r], &block)
  end
  module_function :popen3

  # Open3.popen2 is similer to Open3.popen3 except it doesn't make a pipe for
  # the standard error stream.
  #
  # Block form:
  #
  #   Open3.popen2(cmd... [, opts]) {|stdin, stdout, wait_thr|
  #     pid = wait_thr.pid # pid of the started process.
  #     ...
  #     exit_status = wait_thr.value # Process::Status object returned.
  #   }
  #
  # Non-block form:
  #   
  #   stdin, stdout, wait_thr = Open3.popen2(cmd... [, opts])
  #   ...
  #   stdin.close  # stdin and stdout should be closed explicitly in this form.
  #   stdout.close
  #
  def popen2(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[STDIN] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[STDOUT] = out_w

    popen_run(cmd, opts, [in_r, out_w], [in_w, out_r], &block)
  end
  module_function :popen2

  # Open3.popen2e is similer to Open3.popen3 except it merges
  # the standard output stream and the standard error stream.
  #
  # Block form:
  #
  #   Open3.popen2e(cmd... [, opts]) {|stdin, stdout_and_stderr, wait_thr|
  #     pid = wait_thr.pid # pid of the started process.
  #     ...
  #     exit_status = wait_thr.value # Process::Status object returned.
  #   }
  #
  # Non-block form:
  #   
  #   stdin, stdout_and_stderr, wait_thr = Open3.popen2e(cmd... [, opts])
  #   ...
  #   stdin.close  # stdin and stdout_and_stderr should be closed explicitly in this form.
  #   stdout_and_stderr.close
  #
  def popen2e(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[STDIN] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[[STDOUT, STDERR]] = out_w

    popen_run(cmd, opts, [in_r, out_w], [in_w, out_r], &block)
  end
  module_function :popen2e

  def popen_run(cmd, opts, child_io, parent_io) # :nodoc:
    pid = spawn(*cmd, opts)
    wait_thr = Process.detach(pid)
    child_io.each {|io| io.close }
    result = [*parent_io, wait_thr]
    if defined? yield
      begin
	return yield(*result)
      ensure
	parent_io.each{|io| io.close unless io.closed?}
        wait_thr.join
      end
    end
    result
  end
  module_function :popen_run
  class << self
    private :popen_run
  end

  # Open3.poutput3 captures the standard output and the standard error of a command.
  #
  #   stdout_str, stderr_str, status = Open3.poutput3(cmd... [, opts])
  #
  # The arguments cmd and opts are passed to Open3.popen3 except opts[:stdin_data].
  #
  # If opts[:stdin_data] is specified, it is sent to the command's standard input.
  #
  def poutput3(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    stdin_data = opts.delete(:stdin_data) || ''

    popen3(*cmd, opts) {|i, o, e, t|
      out_reader = Thread.new { o.read }
      err_reader = Thread.new { e.read }
      i.write stdin_data
      i.close
      [out_reader.value, err_reader.value, t.value]
    }
  end
  module_function :poutput3

  # Open3.poutput2 captures the standard output of a command.
  #
  #   stdout_str, status = Open3.poutput2(cmd... [, opts])
  #
  # The arguments cmd and opts are passed to Open3.popen2 except opts[:stdin_data].
  #
  # If opts[:stdin_data] is specified, it is sent to the command's standard input.
  #
  def poutput2(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    stdin_data = opts.delete(:stdin_data) || ''

    popen2(*cmd, opts) {|i, o, t|
      out_reader = Thread.new { o.read }
      i.write stdin_data
      i.close
      [out_reader.value, t.value]
    }
  end
  module_function :poutput2

  # Open3.poutput2e captures the standard output and the standard error of a command.
  #
  #   stdout_and_stderr_str, status = Open3.poutput2e(cmd... [, opts])
  #
  # The arguments cmd and opts are passed to Open3.popen2e except opts[:stdin_data].
  #
  # If opts[:stdin_data] is specified, it is sent to the command's standard input.
  #
  def poutput2e(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    stdin_data = opts.delete(:stdin_data) || ''

    popen2e(*cmd, opts) {|i, oe, t|
      outerr_reader = Thread.new { oe.read }
      i.write stdin_data
      i.close
      [outerr_reader.value, t.value]
    }
  end
  module_function :poutput2e

  # Open3.pipeline_rw starts list of commands as a pipeline with pipes
  # which connects stdin of the first command and stdout of the last command.
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
  # If it is an array, the elements are passed to Kernel#spawn.
  #
  # The option to pass Kernel#spawn is constructed by merging
  # +opts+, the last hash element of the array and
  # specification for the pipe between each commands.
  #
  # Example:
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
    opts[STDIN] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[STDOUT] = out_w

    pipeline_run(cmds, opts, [in_r, out_w], [in_w, out_r], &block)
  end
  module_function :pipeline_rw

  # Open3.pipeline_r starts list of commands as a pipeline with a pipe
  # which connects stdout of the last command.
  #
  #   Open3.pipeline_r(cmd1, cmd2, ... [, opts]) {|last_stdout, wait_threads|
  #     ...
  #   }
  #
  #   last_stdout, wait_threads = Open3.pipeline_r(cmd1, cmd2, ... [, opts])
  #   ...
  #   last_stdout.close
  #
  # Example:
  #
  #   Open3.pipeline_r("yes", "head -10") {|r, ts|
  #     p r.read      #=> "y\ny\ny\ny\ny\ny\ny\ny\ny\ny\n"
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
    opts[STDOUT] = out_w

    pipeline_run(cmds, opts, [out_w], [out_r], &block)
  end
  module_function :pipeline_r

  # Open3.pipeline_w starts list of commands as a pipeline with a pipe
  # which connects stdin of the first command.
  #
  #   Open3.pipeline_w(cmd1, cmd2, ... [, opts]) {|first_stdin, wait_threads|
  #     ...
  #   }
  #
  #   first_stdin, wait_threads = Open3.pipeline_w(cmd1, cmd2, ... [, opts])
  #   ...
  #   first_stdin.close
  #
  # Example:
  #
  #   Open3.pipeline_w("cat -n", "bzip2 -c", STDOUT=>"/tmp/z.bz2") {|w, ts|
  #     w.puts "hello" 
  #     w.close
  #     p ts[0].value
  #     p ts[1].value
  #   }
  #
  def pipeline_w(*cmds, &block)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[STDIN] = in_r
    in_w.sync = true

    pipeline_run(cmds, opts, [in_r], [in_w], &block)
  end
  module_function :pipeline_w

  def pipeline_run(cmds, pipeline_opts, child_io, parent_io, &block) # :nodoc:
    if cmds.empty?
      raise ArgumentError, "no commands"
    end

    opts_base = pipeline_opts.dup
    opts_base.delete STDIN
    opts_base.delete STDOUT

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
        if !cmd_opts.include?(STDIN)
          if pipeline_opts.include?(STDIN)
            cmd_opts[STDIN] = pipeline_opts[STDIN]
          end
        end
      else
        cmd_opts[STDIN] = r
      end
      if i != cmds.length - 1
        r2, w2 = IO.pipe
        cmd_opts[STDOUT] = w2
      else
        if !cmd_opts.include?(STDOUT)
          if pipeline_opts.include?(STDOUT)
            cmd_opts[STDOUT] = pipeline_opts[STDOUT]
          end
        end
      end
      pid = spawn(*cmd, cmd_opts)
      wait_thrs << Process.detach(pid)
      r.close if r
      w2.close if w2
      r = r2
    }
    result = parent_io + [wait_thrs]
    child_io.each {|io| io.close }
    if defined? yield
      begin
	return yield(*result)
      ensure
	parent_io.each{|io| io.close unless io.closed?}
        wait_thrs.each {|t| t.join }
      end
    end
    result
  end
  module_function :pipeline_run
  class << self
    private :pipeline_run
  end

end

if $0 == __FILE__
  a = Open3.popen3("nroff -man")
  Thread.start do
    while line = gets
      a[0].print line
    end
    a[0].close
  end
  while line = a[1].gets
    print ":", line
  end
end
