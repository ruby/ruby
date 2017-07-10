require 'net/protocol'

##
# Aaron Patterson's monkeypatch (accepted into 1.9.1) to fix Net::HTTP's speed
# problems.
#
# http://gist.github.com/251244

class Net::BufferedIO #:nodoc:
  alias :old_rbuf_fill :rbuf_fill

  def rbuf_fill
    if @io.respond_to? :read_nonblock then
      begin
        @rbuf << @io.read_nonblock(65536)
      rescue Errno::EWOULDBLOCK, Errno::EAGAIN => e
        retry if IO.select [@io], nil, nil, @read_timeout
        raise Timeout::Error, e.message
      end
    else # SSL sockets do not have read_nonblock
      timeout @read_timeout do
        @rbuf << @io.sysread(65536)
      end
    end
  end
end if RUBY_VERSION < '1.9'

