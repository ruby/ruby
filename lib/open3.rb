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
# Open3 grants you access to stdin, stdout, and stderr when running another
# program. Example:
#
#   require "open3"
#   include Open3
#   
#   stdin, stdout, stderr = popen3('nroff -man')
#
# If the exit status of the child process is required, Open3.popen3w is usable.
#
# Open3.popen3 can also take a block which will receive stdin, stdout and
# stderr as parameters.  This ensures stdin, stdout and stderr are closed
# once the block exits. Example:
#
#   require "open3"
#
#   Open3.popen3('nroff -man') { |stdin, stdout, stderr| ... }
#

module Open3
  # 
  # Open stdin, stdout, and stderr streams and start external executable.
  #
  # Non-block form:
  #   
  #   stdin, stdout, stderr = Open3.popen3(cmd)
  #   ...
  #   stdin.close  # stdin, stdout and stderr should be closed in this form.
  #   stdout.close
  #   stderr.close
  #
  # Block form:
  #
  #   Open3.popen3(cmd) { |stdin, stdout, stderr| ... }
  #   # stdin, stdout and stderr is closed automatically in this form.
  #
  # The parameter +cmd+ is passed directly to Kernel#spawn.
  #
  def popen3(*cmd)
    if defined? yield
      popen3w(*cmd) {|stdin, stdout, stderr, wait_thr|
        yield stdin, stdout, stderr
      }
    else
      stdin, stdout, stderr, wait_thr = popen3w(*cmd)
      return stdin, stdout, stderr
    end
  end
  module_function :popen3

  # 
  # Open stdin, stdout, and stderr streams and start external executable.
  # In addition, a thread for waiting the started process is noticed.
  # The thread has a thread variable :pid which is the pid of the started
  # process.
  #
  # Non-block form:
  #   
  #   stdin, stdout, stderr, wait_thr = Open3.popen3w(cmd)
  #   pid = wait_thr[:pid]  # pid of the started process.
  #   ...
  #   stdin.close  # stdin, stdout and stderr should be closed in this form.
  #   stdout.close
  #   stderr.close
  #   exit_status = wait_thr.value  # Process::Status object returned.
  #
  # Block form:
  #
  #   Open3.popen3w(cmd) { |stdin, stdout, stderr, wait_thr| ... }
  #
  # The parameter +cmd+ is passed directly to Kernel#spawn.
  #
  # wait_thr.value waits the termination of the process.
  # The block form also waits the process when it returns.
  #
  # Closing stdin, stdout and stderr does not wait the process.
  #
  def popen3w(*cmd)
    pw = IO::pipe   # pipe[0] for read, pipe[1] for write
    pr = IO::pipe
    pe = IO::pipe

    pid = spawn(*cmd, STDIN=>pw[0], STDOUT=>pr[1], STDERR=>pe[1])
    wait_thr = Process.detach(pid)
    wait_thr[:pid] = pid
    pw[0].close
    pr[1].close
    pe[1].close
    pi = [pw[1], pr[0], pe[0], wait_thr]
    pw[1].sync = true
    if defined? yield
      begin
	return yield(*pi)
      ensure
	[pw[1], pr[0], pe[0]].each{|p| p.close unless p.closed?}
        wait_thr.join
      end
    end
    pi
  end
  module_function :popen3w
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
