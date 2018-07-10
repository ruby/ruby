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
  src = Zero.new
  dst = File.open(IO::NULL, 'wb')
  n = IO.copy_stream(src, dst)
rescue Errno::ENOENT
  # not *nix
end if IO.respond_to?(:copy_stream) && IO.const_defined?(:NULL)
