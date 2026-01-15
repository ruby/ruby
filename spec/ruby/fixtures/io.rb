module IOSpec
  def self.exhaust_write_buffer(io)
    written = 0
    buf = " " * 4096

    while true
      written += io.write_nonblock(buf)
    end
  rescue Errno::EAGAIN, Errno::EWOULDBLOCK
    written
  end
end
