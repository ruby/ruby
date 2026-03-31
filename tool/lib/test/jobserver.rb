module Test
  module JobServer
  end
end

class << Test::JobServer
  def connect(makeflags = ENV["MAKEFLAGS"])
    return unless /(?:\A|\s)--jobserver-(?:auth|fds)=(?:(\d+),(\d+)|fifo:((?:\\.|\S)+))/ =~ makeflags
    begin
      if fifo = $3
        fifo.gsub!(/\\(?=.)/, '')
        r = File.open(fifo, IO::RDONLY|IO::NONBLOCK|IO::BINARY)
        w = File.open(fifo, IO::WRONLY|IO::NONBLOCK|IO::BINARY)
      else
        r = IO.for_fd($1.to_i(10), "rb", autoclose: false)
        w = IO.for_fd($2.to_i(10), "wb", autoclose: false)
      end
    rescue
      r&.close
      nil
    else
      return r, w
    end
  end

  def acquire_possible(r, w, max)
    return unless tokens = r.read_nonblock(max - 1, exception: false)
    if (jobs = tokens.size) > 0
      jobserver, w = w, nil
      at_exit do
        jobserver.print(tokens)
        jobserver.close
      end
    end
    return jobs + 1
  rescue Errno::EBADF
  ensure
    r&.close
    w&.close
  end

  def max_jobs(max = 2, makeflags = ENV["MAKEFLAGS"])
    if max > 1 and (r, w = connect(makeflags))
      acquire_possible(r, w, max)
    end
  end
end
