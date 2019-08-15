class << Thread
  # call-seq:
  #    Thread.exclusive { block }   -> obj
  #
  # Wraps the block in a single, VM-global Mutex.synchronize, returning the
  # value of the block. A thread executing inside the exclusive section will
  # only block other threads which also use the Thread.exclusive mechanism.
  def exclusive(&block) end if false
  mutex = Mutex.new # :nodoc:
  define_method(:exclusive) do |&block|
    warn "Thread.exclusive is deprecated, use Thread::Mutex", caller
    mutex.synchronize(&block)
  end
end

class IO

  # call-seq:
  #    ios.read_nonblock(maxlen [, options])              -> string
  #    ios.read_nonblock(maxlen, outbuf [, options])      -> outbuf
  #
  # Reads at most <i>maxlen</i> bytes from <em>ios</em> using
  # the read(2) system call after O_NONBLOCK is set for
  # the underlying file descriptor.
  #
  # If the optional <i>outbuf</i> argument is present,
  # it must reference a String, which will receive the data.
  # The <i>outbuf</i> will contain only the received data after the method call
  # even if it is not empty at the beginning.
  #
  # read_nonblock just calls the read(2) system call.
  # It causes all errors the read(2) system call causes: Errno::EWOULDBLOCK, Errno::EINTR, etc.
  # The caller should care such errors.
  #
  # If the exception is Errno::EWOULDBLOCK or Errno::EAGAIN,
  # it is extended by IO::WaitReadable.
  # So IO::WaitReadable can be used to rescue the exceptions for retrying
  # read_nonblock.
  #
  # read_nonblock causes EOFError on EOF.
  #
  # On some platforms, such as Windows, non-blocking mode is not supported
  # on IO objects other than sockets. In such cases, Errno::EBADF will
  # be raised.
  #
  # If the read byte buffer is not empty,
  # read_nonblock reads from the buffer like readpartial.
  # In this case, the read(2) system call is not called.
  #
  # When read_nonblock raises an exception kind of IO::WaitReadable,
  # read_nonblock should not be called
  # until io is readable for avoiding busy loop.
  # This can be done as follows.
  #
  #   # emulates blocking read (readpartial).
  #   begin
  #     result = io.read_nonblock(maxlen)
  #   rescue IO::WaitReadable
  #     IO.select([io])
  #     retry
  #   end
  #
  # Although IO#read_nonblock doesn't raise IO::WaitWritable.
  # OpenSSL::Buffering#read_nonblock can raise IO::WaitWritable.
  # If IO and SSL should be used polymorphically,
  # IO::WaitWritable should be rescued too.
  # See the document of OpenSSL::Buffering#read_nonblock for sample code.
  #
  # Note that this method is identical to readpartial
  # except the non-blocking flag is set.
  #
  # By specifying a keyword argument _exception_ to +false+, you can indicate
  # that read_nonblock should not raise an IO::WaitReadable exception, but
  # return the symbol +:wait_readable+ instead. At EOF, it will return nil
  # instead of raising EOFError.
  def read_nonblock(len, buf = nil, exception: true)
    __read_nonblock(len, buf, exception)
  end

  # call-seq:
  #    ios.write_nonblock(string)   -> integer
  #    ios.write_nonblock(string [, options])   -> integer
  #
  # Writes the given string to <em>ios</em> using
  # the write(2) system call after O_NONBLOCK is set for
  # the underlying file descriptor.
  #
  # It returns the number of bytes written.
  #
  # write_nonblock just calls the write(2) system call.
  # It causes all errors the write(2) system call causes: Errno::EWOULDBLOCK, Errno::EINTR, etc.
  # The result may also be smaller than string.length (partial write).
  # The caller should care such errors and partial write.
  #
  # If the exception is Errno::EWOULDBLOCK or Errno::EAGAIN,
  # it is extended by IO::WaitWritable.
  # So IO::WaitWritable can be used to rescue the exceptions for retrying write_nonblock.
  #
  #   # Creates a pipe.
  #   r, w = IO.pipe
  #
  #   # write_nonblock writes only 65536 bytes and return 65536.
  #   # (The pipe size is 65536 bytes on this environment.)
  #   s = "a" * 100000
  #   p w.write_nonblock(s)     #=> 65536
  #
  #   # write_nonblock cannot write a byte and raise EWOULDBLOCK (EAGAIN).
  #   p w.write_nonblock("b")   # Resource temporarily unavailable (Errno::EAGAIN)
  #
  # If the write buffer is not empty, it is flushed at first.
  #
  # When write_nonblock raises an exception kind of IO::WaitWritable,
  # write_nonblock should not be called
  # until io is writable for avoiding busy loop.
  # This can be done as follows.
  #
  #   begin
  #     result = io.write_nonblock(string)
  #   rescue IO::WaitWritable, Errno::EINTR
  #     IO.select(nil, [io])
  #     retry
  #   end
  #
  # Note that this doesn't guarantee to write all data in string.
  # The length written is reported as result and it should be checked later.
  #
  # On some platforms such as Windows, write_nonblock is not supported
  # according to the kind of the IO object.
  # In such cases, write_nonblock raises <code>Errno::EBADF</code>.
  #
  # By specifying a keyword argument _exception_ to +false+, you can indicate
  # that write_nonblock should not raise an IO::WaitWritable exception, but
  # return the symbol +:wait_writable+ instead.
  def write_nonblock(buf, exception: true)
    __write_nonblock(buf, exception)
  end
end

class TracePoint
  # call-seq:
  #    trace.enable(target: nil, target_line: nil, target_thread: nil)    -> true or false
  #    trace.enable(target: nil, target_line: nil, target_thread: nil) { block }  -> obj
  #
  # Activates the trace.
  #
  # Returns +true+ if trace was enabled.
  # Returns +false+ if trace was disabled.
  #
  #   trace.enabled?  #=> false
  #   trace.enable    #=> false (previous state)
  #                   #   trace is enabled
  #   trace.enabled?  #=> true
  #   trace.enable    #=> true (previous state)
  #                   #   trace is still enabled
  #
  # If a block is given, the trace will only be enabled within the scope of the
  # block.
  #
  #    trace.enabled?
  #    #=> false
  #
  #    trace.enable do
  #      trace.enabled?
  #      # only enabled for this block
  #    end
  #
  #    trace.enabled?
  #    #=> false
  #
  # +target+, +target_line+ and +target_thread+ parameters are used to
  # limit tracing only to specified code objects. +target+ should be a
  # code object for which RubyVM::InstructionSequence.of will return
  # an instruction sequence.
  #
  #    t = TracePoint.new(:line) { |tp| p tp }
  #
  #    def m1
  #      p 1
  #    end
  #
  #    def m2
  #      p 2
  #    end
  #
  #    t.enable(target: method(:m1))
  #
  #    m1
  #    # prints #<TracePoint:line@test.rb:5 in `m1'>
  #    m2
  #    # prints nothing
  #
  # Note: You cannot access event hooks within the +enable+ block.
  #
  #    trace.enable { p tp.lineno }
  #    #=> RuntimeError: access from outside
  #
  def enable target: nil, target_line: nil, target_thread: nil, &blk
    self.__enable target, target_line, target_thread, &blk
  end
end

class Binding
  # :nodoc:
  def irb
    require 'irb'
    irb
  end

  # suppress redefinition warning
  alias irb irb # :nodoc:
end

module Kernel
  def pp(*objs)
    require 'pp'
    pp(*objs)
  end

  # suppress redefinition warning
  alias pp pp # :nodoc:

  private :pp
end
