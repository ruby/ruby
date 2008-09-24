class CGI

  $CGI_ENV = ENV    # for FCGI support

  # String for carriage return
  CR  = "\015"

  # String for linefeed
  LF  = "\012"

  # Standard internet newline sequence
  EOL = CR + LF

  REVISION = '$Id$' #:nodoc:

  NEEDS_BINMODE = true if /WIN/i.match(RUBY_PLATFORM) 

  # Path separators in different environments.
  PATH_SEPARATOR = {'UNIX'=>'/', 'WINDOWS'=>'\\', 'MACINTOSH'=>':'}

  # HTTP status codes.
  HTTP_STATUS = {
    "OK"                  => "200 OK",
    "PARTIAL_CONTENT"     => "206 Partial Content",
    "MULTIPLE_CHOICES"    => "300 Multiple Choices",
    "MOVED"               => "301 Moved Permanently",
    "REDIRECT"            => "302 Found",
    "NOT_MODIFIED"        => "304 Not Modified",
    "BAD_REQUEST"         => "400 Bad Request",
    "AUTH_REQUIRED"       => "401 Authorization Required",
    "FORBIDDEN"           => "403 Forbidden",
    "NOT_FOUND"           => "404 Not Found",
    "METHOD_NOT_ALLOWED"  => "405 Method Not Allowed",
    "NOT_ACCEPTABLE"      => "406 Not Acceptable",
    "LENGTH_REQUIRED"     => "411 Length Required",
    "PRECONDITION_FAILED" => "412 Rrecondition Failed",
    "SERVER_ERROR"        => "500 Internal Server Error",
    "NOT_IMPLEMENTED"     => "501 Method Not Implemented",
    "BAD_GATEWAY"         => "502 Bad Gateway",
    "VARIANT_ALSO_VARIES" => "506 Variant Also Negotiates"
  }

  # Abbreviated day-of-week names specified by RFC 822
  RFC822_DAYS = %w[ Sun Mon Tue Wed Thu Fri Sat ]

  # Abbreviated month names specified by RFC 822
  RFC822_MONTHS = %w[ Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec ]

  # :startdoc:

  def env_table 
    ENV
  end

  def stdinput
    $stdin
  end

  def stdoutput
    $stdout
  end

  private :env_table, :stdinput, :stdoutput


  # Create an HTTP header block as a string.
  #
  # Includes the empty line that ends the header block.
  #
  # +options+ can be a string specifying the Content-Type (defaults
  # to text/html), or a hash of header key/value pairs.  The following
  # header keys are recognized:
  #
  # type:: the Content-Type header.  Defaults to "text/html"
  # charset:: the charset of the body, appended to the Content-Type header.
  # nph:: a boolean value.  If true, prepend protocol string and status code, and
  #       date; and sets default values for "server" and "connection" if not
  #       explicitly set.
  # status:: the HTTP status code, returned as the Status header.  See the
  #          list of available status codes below.
  # server:: the server software, returned as the Server header.
  # connection:: the connection type, returned as the Connection header (for 
  #              instance, "close".
  # length:: the length of the content that will be sent, returned as the
  #          Content-Length header.
  # language:: the language of the content, returned as the Content-Language
  #            header.
  # expires:: the time on which the current content expires, as a +Time+
  #           object, returned as the Expires header.
  # cookie:: a cookie or cookies, returned as one or more Set-Cookie headers.
  #          The value can be the literal string of the cookie; a CGI::Cookie
  #          object; an Array of literal cookie strings or Cookie objects; or a 
  #          hash all of whose values are literal cookie strings or Cookie objects.
  #          These cookies are in addition to the cookies held in the
  #          @output_cookies field.
  #
  # Other header lines can also be set; they are appended as key: value.
  # 
  #   header
  #     # Content-Type: text/html
  # 
  #   header("text/plain")
  #     # Content-Type: text/plain
  # 
  #   header("nph"        => true,
  #          "status"     => "OK",  # == "200 OK"
  #            # "status"     => "200 GOOD",
  #          "server"     => ENV['SERVER_SOFTWARE'],
  #          "connection" => "close",
  #          "type"       => "text/html",
  #          "charset"    => "iso-2022-jp",
  #            # Content-Type: text/html; charset=iso-2022-jp
  #          "length"     => 103,
  #          "language"   => "ja",
  #          "expires"    => Time.now + 30,
  #          "cookie"     => [cookie1, cookie2],
  #          "my_header1" => "my_value"
  #          "my_header2" => "my_value")
  # 
  # The status codes are:
  # 
  #   "OK"                  --> "200 OK"
  #   "PARTIAL_CONTENT"     --> "206 Partial Content"
  #   "MULTIPLE_CHOICES"    --> "300 Multiple Choices"
  #   "MOVED"               --> "301 Moved Permanently"
  #   "REDIRECT"            --> "302 Found"
  #   "NOT_MODIFIED"        --> "304 Not Modified"
  #   "BAD_REQUEST"         --> "400 Bad Request"
  #   "AUTH_REQUIRED"       --> "401 Authorization Required"
  #   "FORBIDDEN"           --> "403 Forbidden"
  #   "NOT_FOUND"           --> "404 Not Found"
  #   "METHOD_NOT_ALLOWED"  --> "405 Method Not Allowed"
  #   "NOT_ACCEPTABLE"      --> "406 Not Acceptable"
  #   "LENGTH_REQUIRED"     --> "411 Length Required"
  #   "PRECONDITION_FAILED" --> "412 Precondition Failed"
  #   "SERVER_ERROR"        --> "500 Internal Server Error"
  #   "NOT_IMPLEMENTED"     --> "501 Method Not Implemented"
  #   "BAD_GATEWAY"         --> "502 Bad Gateway"
  #   "VARIANT_ALSO_VARIES" --> "506 Variant Also Negotiates"
  # 
  # This method does not perform charset conversion. 
  def header(options='text/html')
    if options.is_a?(String)
      content_type = options
      buf = _header_for_string(content_type)
    elsif options.is_a?(Hash)
      if options.size == 1 && options.has_key?('type')
        content_type = options['type']
        buf = _header_for_string(content_type)
      else
        buf = _header_for_hash(options.dup)
      end
    else
      raise ArgumentError.new("expected String or Hash but got #{options.class}")
    end
    if defined?(MOD_RUBY)
      _header_for_modruby(buf)
      return ''
    else
      buf << EOL    # empty line of separator
      return buf
    end
  end # header()

  def _header_for_string(content_type) #:nodoc:
    buf = ''
    if nph?()
      buf << "#{$CGI_ENV['SERVER_PROTOCOL'] || 'HTTP/1.0'} 200 OK#{EOL}"
      buf << "Date: #{CGI.rfc1123_date(Time.now)}#{EOL}"
      buf << "Server: #{$CGI_ENV['SERVER_SOFTWARE']}#{EOL}"
      buf << "Connection: close#{EOL}"
    end
    buf << "Content-Type: #{content_type}#{EOL}"
    if @output_cookies
      @output_cookies.each {|cookie| buf << "Set-Cookie: #{cookie}#{EOL}" }
    end
    return buf
  end # _header_for_string
  private :_header_for_string

  def _header_for_hash(options)  #:nodoc:
    buf = ''
    ## add charset to option['type']
    options['type'] ||= 'text/html'
    charset = options.delete('charset')
    options['type'] += "; charset=#{charset}" if charset
    ## NPH
    options.delete('nph') if defined?(MOD_RUBY)
    if options.delete('nph') || nph?()
      protocol = $CGI_ENV['SERVER_PROTOCOL'] || 'HTTP/1.0'
      status = options.delete('status')
      status = HTTP_STATUS[status] || status || '200 OK'
      buf << "#{protocol} #{status}#{EOL}"
      buf << "Date: #{CGI.rfc1123_date(Time.now)}#{EOL}"
      options['server'] ||= $CGI_ENV['SERVER_SOFTWARE'] || ''
      options['connection'] ||= 'close'
    end
    ## common headers
    status = options.delete('status')
    buf << "Status: #{HTTP_STATUS[status] || status}#{EOL}" if status
    server = options.delete('server')
    buf << "Server: #{server}#{EOL}" if server
    connection = options.delete('connection')
    buf << "Connection: #{connection}#{EOL}" if connection
    type = options.delete('type')
    buf << "Content-Type: #{type}#{EOL}" #if type
    length = options.delete('length')
    buf << "Content-Length: #{length}#{EOL}" if length
    language = options.delete('language')
    buf << "Content-Language: #{language}#{EOL}" if language
    expires = options.delete('expires')
    buf << "Expires: #{CGI.rfc1123_date(expires)}#{EOL}" if expires
    ## cookie
    if cookie = options.delete('cookie')
      case cookie
      when String, Cookie
        buf << "Set-Cookie: #{cookie}#{EOL}"
      when Array
        arr = cookie
        arr.each {|c| buf << "Set-Cookie: #{c}#{EOL}" }
      when Hash
        hash = cookie
        hash.each {|name, c| buf << "Set-Cookie: #{c}#{EOL}" }
      end
    end
    if @output_cookies
      @output_cookies.each {|c| buf << "Set-Cookie: #{c}#{EOL}" }
    end
    ## other headers
    options.each do |key, value|
      buf << "#{key}: #{value}#{EOL}"
    end
    return buf
  end # _header_for_hash
  private :_header_for_hash

  def nph?  #:nodoc:
    return /IIS\/(\d+)/.match($CGI_ENV['SERVER_SOFTWARE']) && $1.to_i < 5
  end

  def _header_for_modruby(buf)  #:nodoc:
    request = Apache::request
    buf.scan(/([^:]+): (.+)#{EOL}/o) do |name, value|
      warn sprintf("name:%s value:%s\n", name, value) if $DEBUG
      case name
      when 'Set-Cookie'
        request.headers_out.add(name, value)
      when /^status$/i
        request.status_line = value
        request.status = value.to_i
      when /^content-type$/i
        request.content_type = value
      when /^content-encoding$/i
        request.content_encoding = value
      when /^location$/i
        request.status = 302 if request.status == 200
        request.headers_out[name] = value
      else
        request.headers_out[name] = value
      end
    end
    request.send_http_header
    return ''
  end
  private :_header_for_modruby
  #

  # Print an HTTP header and body to $DEFAULT_OUTPUT ($>)
  #
  # The header is provided by +options+, as for #header().
  # The body of the document is that returned by the passed-
  # in block.  This block takes no arguments.  It is required.
  #
  #   cgi = CGI.new
  #   cgi.out{ "string" }
  #     # Content-Type: text/html
  #     # Content-Length: 6
  #     #
  #     # string
  # 
  #   cgi.out("text/plain") { "string" }
  #     # Content-Type: text/plain
  #     # Content-Length: 6
  #     #
  #     # string
  # 
  #   cgi.out("nph"        => true,
  #           "status"     => "OK",  # == "200 OK"
  #           "server"     => ENV['SERVER_SOFTWARE'],
  #           "connection" => "close",
  #           "type"       => "text/html",
  #           "charset"    => "iso-2022-jp",
  #             # Content-Type: text/html; charset=iso-2022-jp
  #           "language"   => "ja",
  #           "expires"    => Time.now + (3600 * 24 * 30),
  #           "cookie"     => [cookie1, cookie2],
  #           "my_header1" => "my_value",
  #           "my_header2" => "my_value") { "string" }
  # 
  # Content-Length is automatically calculated from the size of
  # the String returned by the content block.
  #
  # If ENV['REQUEST_METHOD'] == "HEAD", then only the header
  # is outputted (the content block is still required, but it
  # is ignored).
  # 
  # If the charset is "iso-2022-jp" or "euc-jp" or "shift_jis" then
  # the content is converted to this charset, and the language is set 
  # to "ja".
  def out(options = "text/html") # :yield:

    options = { "type" => options } if options.kind_of?(String)
    content = yield
    options["length"] = content.bytesize.to_s
    output = stdoutput
    output.binmode if defined? output.binmode
    output.print header(options)
    output.print content unless "HEAD" == env_table['REQUEST_METHOD']
  end


  # Print an argument or list of arguments to the default output stream
  #
  #   cgi = CGI.new
  #   cgi.print    # default:  cgi.print == $DEFAULT_OUTPUT.print
  def print(*options)
    stdoutput.print(*options)
  end

  # Parse an HTTP query string into a hash of key=>value pairs.
  #
  #   params = CGI::parse("query_string")
  #     # {"name1" => ["value1", "value2", ...],
  #     #  "name2" => ["value1", "value2", ...], ... }
  #
  def CGI::parse(query)
    params = {}
    query.split(/[&;]/).each do |pairs|
      key, value = pairs.split('=',2).collect{|v| CGI::unescape(v) }
      params.has_key?(key) ? params[key].push(value) : params[key] = [value]
    end
    params.default=[].freeze
    params
  end

  # Mixin module. It provides the follow functionality groups:
  #
  # 1. Access to CGI environment variables as methods.  See 
  #    documentation to the CGI class for a list of these variables.
  #
  # 2. Access to cookies, including the cookies attribute.
  #
  # 3. Access to parameters, including the params attribute, and overloading
  #    [] to perform parameter value lookup by key.
  #
  # 4. The initialize_query method, for initialising the above
  #    mechanisms, handling multipart forms, and allowing the
  #    class to be used in "offline" mode.
  #
  module QueryExtension

    %w[ CONTENT_LENGTH SERVER_PORT ].each do |env|
      define_method(env.sub(/^HTTP_/, '').downcase) do
        (val = env_table[env]) && Integer(val)
      end
    end

    %w[ AUTH_TYPE CONTENT_TYPE GATEWAY_INTERFACE PATH_INFO
        PATH_TRANSLATED QUERY_STRING REMOTE_ADDR REMOTE_HOST
        REMOTE_IDENT REMOTE_USER REQUEST_METHOD SCRIPT_NAME
        SERVER_NAME SERVER_PROTOCOL SERVER_SOFTWARE

        HTTP_ACCEPT HTTP_ACCEPT_CHARSET HTTP_ACCEPT_ENCODING
        HTTP_ACCEPT_LANGUAGE HTTP_CACHE_CONTROL HTTP_FROM HTTP_HOST
        HTTP_NEGOTIATE HTTP_PRAGMA HTTP_REFERER HTTP_USER_AGENT ].each do |env|
      define_method(env.sub(/^HTTP_/, '').downcase) do
        env_table[env]
      end
    end

    # Get the raw cookies as a string.
    def raw_cookie
      env_table["HTTP_COOKIE"]
    end

    # Get the raw RFC2965 cookies as a string.
    def raw_cookie2
      env_table["HTTP_COOKIE2"]
    end

    # Get the cookies as a hash of cookie-name=>Cookie pairs.
    attr_accessor :cookies

    # Get the parameters as a hash of name=>values pairs, where
    # values is an Array.
    attr_reader :params

    # Set all the parameters.
    def params=(hash)
      @params.clear
      @params.update(hash)
    end

    def read_multipart(boundary, content_length)
      params = Hash.new([])
      boundary = "--" + boundary
      quoted_boundary = Regexp.quote(boundary)
      buf = ""
      bufsize = 10 * 1024
      boundary_end=""

      # start multipart/form-data
      stdinput.binmode if defined? stdinput.binmode
      boundary_size = boundary.bytesize + EOL.bytesize
      content_length -= boundary_size
      status = stdinput.read(boundary_size)
      if nil == status
        raise EOFError, "no content body"
      elsif boundary + EOL != status
        raise EOFError, "bad content body"
      end

      loop do
        head = nil
        body = MorphingBody.new

        until head and /#{quoted_boundary}(?:#{EOL}|--)/.match(buf)
          if (not head) and /#{EOL}#{EOL}/.match(buf)
            buf = buf.sub(/\A((?:.|\n)*?#{EOL})#{EOL}/) do
              head = $1.dup
              ""
            end
            next
          end

          if head and ( (EOL + boundary + EOL).bytesize < buf.bytesize )
            body.print buf[0 ... (buf.bytesize - (EOL + boundary + EOL).bytesize)]
            buf[0 ... (buf.bytesize - (EOL + boundary + EOL).bytesize)] = ""
          end

          c = if bufsize < content_length
                stdinput.read(bufsize)
              else
                stdinput.read(content_length)
              end
          if c.nil? || c.empty?
            raise EOFError, "bad content body"
          end
          buf.concat(c)
          content_length -= c.bytesize
        end

        buf = buf.sub(/\A((?:.|\n)*?)(?:[\r\n]{1,2})?#{quoted_boundary}([\r\n]{1,2}|--)/) do
          body.print $1
          if "--" == $2
            content_length = -1
          end
          boundary_end = $2.dup
          ""
        end

        body.rewind

        /Content-Disposition:.* filename=(?:"((?:\\.|[^\"])*)"|([^;\s]*))/i.match(head)
      	filename = ($1 or $2 or "")
	      if /Mac/i =~ env_table['HTTP_USER_AGENT'] and
	          /Mozilla/i =~ env_table['HTTP_USER_AGENT'] and
	          /MSIE/i !~ env_table['HTTP_USER_AGENT']
	        filename = CGI::unescape(filename)
	      end
        
        /Content-Type: ([^\s]*)/i.match(head)
        content_type = ($1 or "")

        (class << body; self; end).class_eval do
          alias local_path path
          define_method(:original_filename) {filename.dup.taint}
          define_method(:content_type) {content_type.dup.taint}
        end

        /Content-Disposition:.* name="?([^\";\s]*)"?/i.match(head)
        name = ($1 || "").dup

        if params.has_key?(name)
          params[name].push(body)
        else
          params[name] = [body]
        end
        break if buf.bytesize == 0
        break if content_length == -1
      end
      raise EOFError, "bad boundary end of body part" unless boundary_end=~/--/

      params
    end # read_multipart
    private :read_multipart

    # offline mode. read name=value pairs on standard input.
    def read_from_cmdline
      require "shellwords"

      string = unless ARGV.empty?
        ARGV.join(' ')
      else
        if STDIN.tty?
          STDERR.print(
            %|(offline mode: enter name=value pairs on standard input)\n|
          )
        end
        readlines.join(' ').gsub(/\n/, '')
      end.gsub(/\\=/, '%3D').gsub(/\\&/, '%26')

      words = Shellwords.shellwords(string)

      if words.find{|x| /=/.match(x) }
        words.join('&')
      else
        words.join('+')
      end
    end
    private :read_from_cmdline

    # A wrapper class to use a StringIO object as the body and switch
    # to a TempFile when the passed threshold is passed.
    class MorphingBody
      begin
        require "stringio"
        @@small_buffer = lambda{StringIO.new}
      rescue LoadError
        require "tempfile"
        @@small_buffer = lambda{
          n = Tempfile.new("CGI")
          n.binmode
          n
        }
      end

      def initialize(morph_threshold = 10240)
        @threshold = morph_threshold
        @body = @@small_buffer.call
        @cur_size = 0
        @morph_check = true
      end

      def print(data)
        if @morph_check && (@cur_size + data.bytesize > @threshold)
          convert_body
        end
        @body.print data
      end
      def rewind
        @body.rewind
      end
      def path
        @body.path
      end

      # returns the true body object.
      def extract
        @body
      end

      private
      def convert_body
        new_body = TempFile.new("CGI")
        new_body.binmode if defined? @body.binmode
        new_body.binmode if defined? new_body.binmode

        @body.rewind
        new_body.print @body.read
        @body = new_body
        @morph_check = false
      end
    end

    # Initialize the data from the query.
    #
    # Handles multipart forms (in particular, forms that involve file uploads).
    # Reads query parameters in the @params field, and cookies into @cookies.
    def initialize_query()
      if ("POST" == env_table['REQUEST_METHOD']) and
         %r|\Amultipart/form-data.*boundary=\"?([^\";,]+)\"?|.match(env_table['CONTENT_TYPE'])
        boundary = $1.dup
        @multipart = true
        @params = read_multipart(boundary, Integer(env_table['CONTENT_LENGTH']))
      else
        @multipart = false
        @params = CGI::parse(
                    case env_table['REQUEST_METHOD']
                    when "GET", "HEAD"
                      if defined?(MOD_RUBY)
                        Apache::request.args or ""
                      else
                        env_table['QUERY_STRING'] or ""
                      end
                    when "POST"
                      stdinput.binmode if defined? stdinput.binmode
                      stdinput.read(Integer(env_table['CONTENT_LENGTH'])) or ''
                    else
                      read_from_cmdline
                    end.dup.force_encoding(@accept_charset)
                  )
        if @accept_charset!="ASCII-8BIT" || @accept_charset!=Encoding::ASCII_8BIT
          @params.each do |key,values|
            values.each do |value|
              unless value.valid_encoding?
                if @accept_charset_error_block
                  @accept_charset_error_block.call(key,value)
                else
                  raise InvalidEncoding,"Accept-Charset encoding error"
                end
              end
            end
          end
        end
      end

      @cookies = CGI::Cookie::parse((env_table['HTTP_COOKIE'] or env_table['COOKIE']))
    end
    private :initialize_query

    def multipart?
      @multipart
    end

    # Get the value for the parameter with a given key.
    #
    # If the parameter has multiple values, only the first will be 
    # retrieved; use #params() to get the array of values.
    def [](key)
      params = @params[key]
      return '' unless params
      value = params[0]
      if @multipart
        if value
          return value
        elsif defined? StringIO
          StringIO.new("")
        else
          Tempfile.new("CGI")
        end
      else
        str = if value then value.dup else "" end
        str
      end
    end

    # Return all parameter keys as an array.
    def keys(*args)
      @params.keys(*args)
    end

    # Returns true if a given parameter key exists in the query.
    def has_key?(*args)
      @params.has_key?(*args)
    end
    alias key? has_key?
    alias include? has_key?

  end # QueryExtension

  # InvalidEncoding Exception class
  class InvalidEncoding < Exception; end

  # @@accept_charset is default accept character set.
  # This default value default is "UTF-8"
  # If you want to change the default accept character set
  # when create a new CGI instance, set this:
  # 
  #   CGI.accept_charset = "EUC-JP"
  #

  @@accept_charset="UTF-8"

  def self.accept_charset
    @@accept_charset
  end

  def self.accept_charset=(accept_charset)
    @@accept_charset=accept_charset
  end

  # Create a new CGI instance.
  #
  # CGI accept constructor parameters either in a hash, string as a block.
  # But string is as same as using :tag_maker of hash.
  #
  #   CGI.new("html3") #=>  CGI.new(:tag_maker=>"html3")
  #
  # And, if you specify string, @accept_charset cannot be changed.
  # Instead, please use hash parameter.
  #
  # == accept_charset
  #
  # :accept_charset specifies encoding of received query string.
  # ( Default value is @@accept_charset. )
  # If not valid, raise CGI::InvalidEncoding
  #
  # Example. Suppose @@accept_charset # => "UTF-8"
  #
  # when not specified:
  #
  #   cgi=CGI.new      # @accept_charset # => "UTF-8"
  #
  # when specified "EUC-JP":
  #
  #   cgi=CGI.new(:accept_charset => "EUC-JP") # => "EUC-JP"
  #
  # == block
  #
  # When you use a block, you can write a process 
  # that query encoding is invalid. Example:
  #
  #   encoding_error={}
  #   cgi=CGI.new(:accept_charset=>"EUC-JP") do |name,value| 
  #     encoding_error[key] = value
  #   end
  #
  # == tag_maker
  #
  # :tag_maker specifies which version of HTML to load the HTML generation
  # methods for.  The following versions of HTML are supported:
  #
  # html3:: HTML 3.x
  # html4:: HTML 4.0
  # html4Tr:: HTML 4.0 Transitional
  # html4Fr:: HTML 4.0 with Framesets
  #
  # If not specified, no HTML generation methods will be loaded.
  #
  # If the CGI object is not created in a standard CGI call environment
  # (that is, it can't locate REQUEST_METHOD in its environment), then
  # it will run in "offline" mode.  In this mode, it reads its parameters
  # from the command line or (failing that) from standard input.  Otherwise,
  # cookies and other parameters are parsed automatically from the standard
  # CGI locations, which varies according to the REQUEST_METHOD. It works this:
  #
  #   CGI.new(:tag_maker=>"html3")
  #
  # This will be obsolete:
  #
  #   CGI.new("html3")
  #
  attr_reader :accept_charset
  def initialize(options = {},&block)
    @accept_charset_error_block=block if block_given?
    @options={:accept_charset=>@@accept_charset}
    case options
    when Hash
      @options.merge!(options)
    when String
      @options[:tag_maker]=options
    end
    @accept_charset=@options[:accept_charset]
    if defined?(MOD_RUBY) && !ENV.key?("GATEWAY_INTERFACE")
      Apache.request.setup_cgi_env
    end

    extend QueryExtension
    @multipart = false

    initialize_query()  # set @params, @cookies
    @output_cookies = nil
    @output_hidden = nil

    case @options[:tag_maker]
    when "html3"
      require 'cgi/html'
      extend Html3
      element_init()
      extend HtmlExtension
    when "html4"
      require 'cgi/html'
      extend Html4
      element_init()
      extend HtmlExtension
    when "html4Tr"
      require 'cgi/html'
      extend Html4Tr
      element_init()
      extend HtmlExtension
    when "html4Fr"
      require 'cgi/html'
      extend Html4Tr
      element_init()
      extend Html4Fr
      element_init()
      extend HtmlExtension
    end
  end

end   # class CGI


