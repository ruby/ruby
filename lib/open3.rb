# Usage:
#	require "open3"
#
#	in, out, err = Open3.popen3('nroff -man')
#  or
#	include Open3
#	in, out, err = popen3('nroff -man')
#

module Open3
  #[stdin, stdout, stderr] = popen3(command);
  def popen3(*cmd)
    pw = IO::pipe   # pipe[0] for read, pipe[1] for write
    pr = IO::pipe
    pe = IO::pipe

    pid = fork{
      # child
      fork{
	# grandchild
	pw[1].close
	STDIN.reopen(pw[0])
	pw[0].close

	pr[0].close
	STDOUT.reopen(pr[1])
	pr[1].close

	pe[0].close
	STDERR.reopen(pe[1])
	pe[1].close

	exec(*cmd)
      }
      exit!
    }

    pw[0].close
    pr[1].close
    pe[1].close
    Process.waitpid(pid)
    pi = [pw[1], pr[0], pe[0]]
    if defined? yield
      begin
	return yield(*pi)
      ensure
	pi.each{|p| p.close unless p.closed?}
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
