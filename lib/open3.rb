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
  #   stdin.close  # stdin, stdout and stderr should be closed in this form.
  #   stdout.close
  #   stderr.close
  #   exit_status = wait_thr.value  # Process::Status object returned.
  #
  # The parameters +cmd...+ is passed to Kernel#spawn.
  # So a commandline string and list of argument strings can be accepted as follows.
  #
  #   Open3.popen3("echo a") {|i, o, e, t| ... }
  #   Open3.popen3("echo", "a") {|i, o, e, t| ... }
  #
  # If the last parameter, opts, is a Hash, it is recognized as an option for Kernel#spawn.
  #
  #   Open3.popen3("pwd", :chdir=>"/") {|i,o,e,t|
  #     p o.read.chomp #=> "/"
  #   }
  #
  # opts[STDIN], opts[STDOUT] and opts[STDERR] in the option are set for redirection.
  #
  # If some of the three elements in opts are specified,
  # pipes for them are not created.
  # In that case, block arugments for the block form and
  # return values for the non-block form are decreased.
  #
  #   # No pipe "e" for stderr
  #   Open3.popen3("echo a", STDERR=>nil) {|i,o,t| ... }
  #   i,o,t = Open3.popen3("echo a", STDERR=>nil)
  #
  # If the value is nil as above, the elements of opts are removed.
  # So standard input/output/error of current process are inherited.
  #
  # If the value is not nil, it is passed as is to Kernel#spawn.
  # So pipeline of commands can be constracted as follows.
  #
  #   Open3.popen3("yes", STDIN=>nil, STDERR=>nil) {|o1,t1|
  #     Open3.popen3("head -10", STDIN=>o1, STDERR=>nil) {|o2,t2|
  #       o1.close
  #       p o2.read     #=> "y\ny\ny\ny\ny\ny\ny\ny\ny\ny\n"
  #       p t1.value    #=> #<Process::Status: pid 13508 SIGPIPE (signal 13)>
  #       p t2.value    #=> #<Process::Status: pid 13510 exit 0>
  #     } 
  #   }
  #
  # wait_thr.value waits the termination of the process.
  # The block form also waits the process when it returns.
  #
  # Closing stdin, stdout and stderr does not wait the process.
  #
  def popen3(*cmd)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    child_io = []
    parent_io = []

    if !opts.include?(STDIN)
      pw = IO.pipe   # pipe[0] for read, pipe[1] for write
      opts[STDIN] = pw[0]
      pw[1].sync = true
      child_io << pw[0]
      parent_io << pw[1]
    elsif opts[STDIN] == nil
      opts.delete(STDIN)
    end

    if !opts.include?(STDOUT)
      pr = IO.pipe
      opts[STDOUT] = pr[1]
      child_io << pr[1]
      parent_io << pr[0]
    elsif opts[STDOUT] == nil
      opts.delete(STDOUT)
    end

    if !opts.include?(STDERR)
      pe = IO.pipe
      opts[STDERR] = pe[1]
      child_io << pe[1]
      parent_io << pe[0]
    elsif opts[STDERR] == nil
      opts.delete(STDERR)
    end

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
  module_function :popen3
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
