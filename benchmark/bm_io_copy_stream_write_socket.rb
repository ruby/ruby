# The goal of this is to use a synthetic (non-IO) reader
# to trigger the read/write loop of IO.copy_stream,
# bypassing in-kernel mechanisms like sendfile for zero copy,
# so we wrap the /dev/zero IO object:
class Zero
  def initialize
    @n = 100000
    @in = File.open('/dev/zero', 'rb')
  end

  def read(len, buf)
    return if (@n -= 1) == 0
    @in.read(len, buf)
  end
end

begin
  require 'socket'
  src = Zero.new
  rd, wr = UNIXSocket.pair
  pid = fork do
    wr.close
    buf = String.new
    while rd.read(16384, buf)
    end
  end
  rd.close
  IO.copy_stream(src, wr)
rescue Errno::ENOENT, NotImplementedError, NameError
  # not *nix: missing /dev/zero, fork, or UNIXSocket
rescue LoadError # no socket?
ensure
  wr.close if wr
  Process.waitpid(pid) if pid
end if IO.respond_to?(:copy_stream)
