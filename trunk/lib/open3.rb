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
  # 
  # Open stdin, stdout, and stderr streams and start external executable.
  # In addition, a thread for waiting the started process is noticed.
  # The thread has a thread variable :pid which is the pid of the started
  # process.
  #
  # Non-block form:
  #   
  #   stdin, stdout, stderr, wait_thr = Open3.popen3(cmd)
  #   pid = wait_thr[:pid]  # pid of the started process.
  #   ...
  #   stdin.close  # stdin, stdout and stderr should be closed in this form.
  #   stdout.close
  #   stderr.close
  #   exit_status = wait_thr.value  # Process::Status object returned.
  #
  # Block form:
  #
  #   Open3.popen3(cmd) { |stdin, stdout, stderr, wait_thr| ... }
  #
  # The parameter +cmd+ is passed directly to Kernel#spawn.
  #
  # wait_thr.value waits the termination of the process.
  # The block form also waits the process when it returns.
  #
  # Closing stdin, stdout and stderr does not wait the process.
  #
  def popen3(*cmd)
    pw = IO::pipe   # pipe[0] for read, pipe[1] for write
    pr = IO::pipe
    pe = IO::pipe

    pid = spawn(*cmd, STDIN=>pw[0], STDOUT=>pr[1], STDERR=>pe[1])
    wait_thr = Process.detach(pid)
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
