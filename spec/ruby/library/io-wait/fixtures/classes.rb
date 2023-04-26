module IOWaitSpec
  def self.exhaust_write_buffer(io)
    written = 0
    buf = " " * 4096

    begin
      written += io.write_nonblock(buf)
    rescue Errno::EAGAIN, Errno::EWOULDBLOCK
      return written
    end while true
  end
end
