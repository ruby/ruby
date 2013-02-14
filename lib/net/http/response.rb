# HTTP response class.
#
# This class wraps together the response header and the response body (the
# entity requested).
#
# It mixes in the HTTPHeader module, which provides access to response
# header values both via hash-like methods and via individual readers.
#
# Note that each possible HTTP response code defines its own
# HTTPResponse subclass.  These are listed below.
#
# All classes are defined under the Net module. Indentation indicates
# inheritance.  For a list of the classes see Net::HTTP.
#
#
class Net::HTTPResponse
  class << self
    # true if the response has a body.
    def body_permitted?
      self::HAS_BODY
    end

    def exception_type   # :nodoc: internal use only
      self::EXCEPTION_TYPE
    end

    def read_new(sock)   #:nodoc: internal use only
      httpv, code, msg = read_status_line(sock)
      res = response_class(code).new(httpv, code, msg)
      each_response_header(sock) do |k,v|
        res.add_field k, v
      end
      res
    end

    private

    def read_status_line(sock)
      str = sock.readline
      m = /\AHTTP(?:\/(\d+\.\d+))?\s+(\d\d\d)\s*(.*)\z/in.match(str) or
        raise Net::HTTPBadResponse, "wrong status line: #{str.dump}"
      m.captures
    end

    def response_class(code)
      CODE_TO_OBJ[code] or
      CODE_CLASS_TO_OBJ[code[0,1]] or
      Net::HTTPUnknownResponse
    end

    def each_response_header(sock)
      key = value = nil
      while true
        line = sock.readuntil("\n", true).sub(/\s+\z/, '')
        break if line.empty?
        if line[0] == ?\s or line[0] == ?\t and value
          value << ' ' unless value.empty?
          value << line.strip
        else
          yield key, value if key
          key, value = line.strip.split(/\s*:\s*/, 2)
          raise Net::HTTPBadResponse, 'wrong header line format' if value.nil?
        end
      end
      yield key, value if key
    end
  end

  # next is to fix bug in RDoc, where the private inside class << self
  # spills out.
  public

  include Net::HTTPHeader

  def initialize(httpv, code, msg)   #:nodoc: internal use only
    @http_version = httpv
    @code         = code
    @message      = msg
    initialize_http_header nil
    @body = nil
    @read = false
    @uri  = nil
    @decode_content = false
  end

  # The HTTP version supported by the server.
  attr_reader :http_version

  # The HTTP result code string. For example, '302'.  You can also
  # determine the response type by examining which response subclass
  # the response object is an instance of.
  attr_reader :code

  # The HTTP result message sent by the server. For example, 'Not Found'.
  attr_reader :message
  alias msg message   # :nodoc: obsolete

  # The URI used to fetch this response.  The response URI is only available
  # if a URI was used to create the request.
  attr_reader :uri

  # Set to true automatically when the request did not contain an
  # Accept-Encoding header from the user.
  attr_accessor :decode_content

  def inspect
    "#<#{self.class} #{@code} #{@message} readbody=#{@read}>"
  end

  #
  # response <-> exception relationship
  #

  def code_type   #:nodoc:
    self.class
  end

  def error!   #:nodoc:
    raise error_type().new(@code + ' ' + @message.dump, self)
  end

  def error_type   #:nodoc:
    self.class::EXCEPTION_TYPE
  end

  # Raises an HTTP error if the response is not 2xx (success).
  def value
    error! unless self.kind_of?(Net::HTTPSuccess)
  end

  def uri= uri # :nodoc:
    @uri = uri.dup if uri
  end

  #
  # header (for backward compatibility only; DO NOT USE)
  #

  def response   #:nodoc:
    warn "#{caller(1)[0]}: warning: Net::HTTPResponse#response is obsolete" if $VERBOSE
    self
  end

  def header   #:nodoc:
    warn "#{caller(1)[0]}: warning: Net::HTTPResponse#header is obsolete" if $VERBOSE
    self
  end

  def read_header   #:nodoc:
    warn "#{caller(1)[0]}: warning: Net::HTTPResponse#read_header is obsolete" if $VERBOSE
    self
  end

  #
  # body
  #

  def reading_body(sock, reqmethodallowbody)  #:nodoc: internal use only
    @socket = sock
    @body_exist = reqmethodallowbody && self.class.body_permitted?
    begin
      yield
      self.body   # ensure to read body
    ensure
      @socket = nil
    end
  end

  # Gets the entity body returned by the remote HTTP server.
  #
  # If a block is given, the body is passed to the block, and
  # the body is provided in fragments, as it is read in from the socket.
  #
  # Calling this method a second or subsequent time for the same
  # HTTPResponse object will return the value already read.
  #
  #   http.request_get('/index.html') {|res|
  #     puts res.read_body
  #   }
  #
  #   http.request_get('/index.html') {|res|
  #     p res.read_body.object_id   # 538149362
  #     p res.read_body.object_id   # 538149362
  #   }
  #
  #   # using iterator
  #   http.request_get('/index.html') {|res|
  #     res.read_body do |segment|
  #       print segment
  #     end
  #   }
  #
  def read_body(dest = nil, &block)
    if @read
      raise IOError, "#{self.class}\#read_body called twice" if dest or block
      return @body
    end
    to = procdest(dest, block)
    stream_check
    if @body_exist
      read_body_0 to
      @body = to
    else
      @body = nil
    end
    @read = true

    @body
  end

  # Returns the full entity body.
  #
  # Calling this method a second or subsequent time will return the
  # string already read.
  #
  #   http.request_get('/index.html') {|res|
  #     puts res.body
  #   }
  #
  #   http.request_get('/index.html') {|res|
  #     p res.body.object_id   # 538149362
  #     p res.body.object_id   # 538149362
  #   }
  #
  def body
    read_body()
  end

  # Because it may be necessary to modify the body, Eg, decompression
  # this method facilitates that.
  def body=(value)
    @body = value
  end

  alias entity body   #:nodoc: obsolete

  private

  ##
  # Checks for a supported Content-Encoding header and yields an Inflate
  # wrapper for this response's socket when zlib is present.  If the
  # Content-Encoding is unsupported or zlib is missing the plain socket is
  # yielded.
  #
  # If a Content-Range header is present a plain socket is yielded as the
  # bytes in the range may not be a complete deflate block.

  def inflater # :nodoc:
    return yield @socket unless Net::HTTP::HAVE_ZLIB
    return yield @socket unless @decode_content
    return yield @socket if self['content-range']

    case self['content-encoding']
    when 'deflate', 'gzip', 'x-gzip' then
      self.delete 'content-encoding'

      inflate_body_io = Inflater.new(@socket)

      begin
        yield inflate_body_io
      ensure
        inflate_body_io.finish
      end
    when 'none', 'identity' then
      self.delete 'content-encoding'

      yield @socket
    else
      yield @socket
    end
  end

  def read_body_0(dest)
    inflater do |inflate_body_io|
      if chunked?
        read_chunked dest, inflate_body_io
        return
      end

      @socket = inflate_body_io

      clen = content_length()
      if clen
        @socket.read clen, dest, true   # ignore EOF
        return
      end
      clen = range_length()
      if clen
        @socket.read clen, dest
        return
      end
      @socket.read_all dest
    end
  end

  ##
  # read_chunked reads from +@socket+ for chunk-size, chunk-extension, CRLF,
  # etc. and +chunk_data_io+ for chunk-data which may be deflate or gzip
  # encoded.
  #
  # See RFC 2616 section 3.6.1 for definitions

  def read_chunked(dest, chunk_data_io) # :nodoc:
    len = nil
    total = 0
    while true
      line = @socket.readline
      hexlen = line.slice(/[0-9a-fA-F]+/) or
          raise Net::HTTPBadResponse, "wrong chunk size line: #{line}"
      len = hexlen.hex
      break if len == 0
      begin
        chunk_data_io.read len, dest
      ensure
        total += len
        @socket.read 2   # \r\n
      end
    end
    until @socket.readline.empty?
      # none
    end
  end

  def stream_check
    raise IOError, 'attempt to read body out of block' if @socket.closed?
  end

  def procdest(dest, block)
    raise ArgumentError, 'both arg and block given for HTTP method' if
      dest and block
    if block
      Net::ReadAdapter.new(block)
    else
      dest || ''
    end
  end

  ##
  # Inflater is a wrapper around Net::BufferedIO that transparently inflates
  # zlib and gzip streams.

  class Inflater # :nodoc:

    ##
    # Creates a new Inflater wrapping +socket+

    def initialize socket
      @socket = socket
      # zlib with automatic gzip detection
      @inflate = Zlib::Inflate.new(32 + Zlib::MAX_WBITS)
    end

    ##
    # Finishes the inflate stream.

    def finish
      @inflate.finish
    end

    ##
    # Returns a Net::ReadAdapter that inflates each read chunk into +dest+.
    #
    # This allows a large response body to be inflated without storing the
    # entire body in memory.

    def inflate_adapter(dest)
      block = proc do |compressed_chunk|
        @inflate.inflate(compressed_chunk) do |chunk|
          dest << chunk
        end
      end

      Net::ReadAdapter.new(block)
    end

    ##
    # Reads +clen+ bytes from the socket, inflates them, then writes them to
    # +dest+.  +ignore_eof+ is passed down to Net::BufferedIO#read
    #
    # Unlike Net::BufferedIO#read, this method returns more than +clen+ bytes.
    # At this time there is no way for a user of Net::HTTPResponse to read a
    # specific number of bytes from the HTTP response body, so this internal
    # API does not return the same number of bytes as were requested.
    #
    # See https://bugs.ruby-lang.org/issues/6492 for further discussion.

    def read clen, dest, ignore_eof = false
      temp_dest = inflate_adapter(dest)

      @socket.read clen, temp_dest, ignore_eof
    end

    ##
    # Reads the rest of the socket, inflates it, then writes it to +dest+.

    def read_all dest
      temp_dest = inflate_adapter(dest)

      @socket.read_all temp_dest
    end

  end

end

