=begin
$Date$

== CGI SUPPORT LIBRARY

cgi.rb

Version 1.61

Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
Copyright (C) 2000  Information-technology Promotion Agency, Japan

Wakou Aoyama <wakou@fsinet.or.jp>


== EXAMPLE

=== GET FORM VALUES

	require "cgi"
	cgi = CGI.new
	values = cgi['field_name']   # <== array of 'field_name'
	  # if not 'field_name' included, then return [].
	fields = cgi.keys            # <== array of field names

	# returns true if form has 'field_name'
	cgi.has_key?('field_name')
	cgi.has_key?('field_name')
	cgi.include?('field_name')


=== GET FORM VALUES AS HASH

	require "cgi"
	cgi = CGI.new
	params = cgi.params

cgi.params is a hash.

	cgi.params['new_field_name'] = ["value"]  # add new param
	cgi.params['field_name'] = ["new_value"]  # change value
	cgi.params.delete('field_name')           # delete param
	cgi.params.clear                          # delete all params


=== SAVE FORM VALUES TO FILE

	require "pstore"
	db = PStore.new("query.db")
	db.transaction do
	  db["params"] = cgi.params
	end


=== RESTORE FORM VALUES FROM FILE

	require "pstore"
	db = PStore.new("query.db")
	db.transaction do
	  cgi.params = db["params"]
	end


=== GET MULTIPART FORM VALUES

	require "cgi"
	cgi = CGI.new
	values = cgi['field_name']   # <== array of 'field_name'
	values[0].read               # <== body of values[0]
	values[0].local_path         # <== path to local file of values[0]
	values[0].original_filename  # <== original filename of values[0]
	values[0].content_type       # <== content_type of values[0]

and values[0] has Tempfile class methods.

(Tempfile class object has File class methods)


=== GET COOKIE VALUES

	require "cgi"
	cgi = CGI.new
	values = cgi.cookies['name']  # <== array of 'name'
	  # if not 'name' included, then return [].
	names = cgi.cookies.keys      # <== array of cookie names

and cgi.cookies is a hash.


=== GET COOKIE OBJECTS

	require "cgi"
	cgi = CGI.new
	for name, cookie in cgi.cookies
	  cookie.expires = Time.now + 30
	end
	cgi.out("cookie" => cgi.cookies){"string"}

	cgi.cookies # { "name1" => cookie1, "name2" => cookie2, ... }

	require "cgi"
	cgi = CGI.new
	cgi.cookies['name'].expires = Time.now + 30
	cgi.out("cookie" => cgi.cookies['name']){"string"}

and see MAKE COOKIE OBJECT.


=== GET ENVIRONMENT VALUE

	require "cgi"
	cgi = CGI.new
	value = cgi.auth_type
	  # ENV["AUTH_TYPE"]

http://www.w3.org/CGI/

AUTH_TYPE CONTENT_LENGTH CONTENT_TYPE GATEWAY_INTERFACE PATH_INFO
PATH_TRANSLATED QUERY_STRING REMOTE_ADDR REMOTE_HOST REMOTE_IDENT
REMOTE_USER REQUEST_METHOD SCRIPT_NAME SERVER_NAME SERVER_PORT
SERVER_PROTOCOL SERVER_SOFTWARE

content_length and server_port return Integer. and the others return String.

and HTTP_COOKIE, HTTP_COOKIE2

	value = cgi.raw_cookie
	  # ENV["HTTP_COOKIE"]
	value = cgi.raw_cookie2
	  # ENV["HTTP_COOKIE2"]

and other HTTP_*

	value = cgi.accept
	  # ENV["HTTP_ACCEPT"]
	value = cgi.accept_charset
	  # ENV["HTTP_ACCEPT_CHARSET"]

HTTP_ACCEPT HTTP_ACCEPT_CHARSET HTTP_ACCEPT_ENCODING HTTP_ACCEPT_LANGUAGE
HTTP_CACHE_CONTROL HTTP_FROM HTTP_HOST HTTP_NEGOTIATE HTTP_PRAGMA
HTTP_REFERER HTTP_USER_AGENT


=== PRINT HTTP HEADER AND HTML STRING TO $DEFAULT_OUTPUT ($>)

	require "cgi"
	cgi = CGI.new("html3")  # add HTML generation methods
	cgi.out() do
	  cgi.html() do
	    cgi.head{ cgi.title{"TITLE"} } +
	    cgi.body() do
	      cgi.form() do
	        cgi.textarea("get_text") +
	        cgi.br +
	        cgi.submit
	      end +
	      cgi.pre() do
	        CGI::escapeHTML(
	          "params: " + cgi.params.inspect + "\n" +
	          "cookies: " + cgi.cookies.inspect + "\n" +
	          ENV.collect() do |key, value|
	            key + " --> " + value + "\n"
	          end.join("")
	        )
	      end
	    end
	  end
	end

	# add HTML generation methods
	CGI.new("html3")    # html3.2
	CGI.new("html4")    # html4.0 (Strict)
	CGI.new("html4Tr")  # html4.0 Transitional
	CGI.new("html4Fr")  # html4.0 Frameset

=end


require 'English'

class CGI

  CR  = "\015"
  LF  = "\012"
  EOL = CR + LF
v = $-v
$-v = false
  VERSION = "1.61"
  RELEASE_DATE = "$Date$"
$-v = v

  NEEDS_BINMODE = true if /WIN/ni === RUBY_PLATFORM
  PATH_SEPARATOR = {'UNIX'=>'/', 'WINDOWS'=>'\\', 'MACINTOSH'=>':'}

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

  RFC822_DAYS = %w[ Sun Mon Tue Wed Thu Fri Sat ]
  RFC822_MONTHS = %w[ Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec ]

  def env_table
    ENV
  end

  def stdinput
    $stdin
  end

  def stdoutput
    $DEFAULT_OUTPUT
  end

  private :env_table, :stdinput, :stdoutput

=begin
== METHODS
=end

=begin
=== ESCAPE URL ENCODE
	url_encoded_string = CGI::escape("string")
=end
  def CGI::escape(string)
    string.gsub(/([^a-zA-Z0-9_.-])/n) do
      if " " == $1
        "+"
      else
        sprintf("%%%02X", $1.unpack("C")[0])
      end
    end
  end


=begin
=== UNESCAPE URL ENCODED
	string = CGI::unescape("url encoded string")
=end
  def CGI::unescape(string)
    string.gsub(/\+/n, ' ').gsub(/%([0-9a-fA-F]{2})/n) do
      [$1.hex].pack("c")
    end
  end


=begin
=== ESCAPE HTML &"<>
	CGI::escapeHTML("string")
=end
  def CGI::escapeHTML(string)
    string.gsub(/&/n, '&amp;').gsub(/\"/n, '&quot;').gsub(/>/n, '&gt;').gsub(/</n, '&lt;')
  end


=begin
=== UNESCAPE HTML
	CGI::unescapeHTML("HTML escaped string")
=end
  def CGI::unescapeHTML(string)
    string.gsub(/&(.*?);/n) do
      match = $1.dup
      case match
      when /\Aamp\z/ni           then '&'
      when /\Aquot\z/ni          then '"'
      when /\Agt\z/ni            then '>'
      when /\Alt\z/ni            then '<'
      when /\A#(\d+)\z/n         then
        if Integer($1) < 256
          Integer($1).chr
        else
          if $KCODE[0] == ?u or $KCODE[0] == ?U
            [Integer($1)].pack("U")
          else
            "#" + $1
          end
        end
      when /\A#x([0-9a-f]+)\z/ni then $1.hex.chr
      end
    end
  end


=begin
=== ESCAPE ELEMENT
	print CGI::escapeElement("<BR><A HREF="url"></A>", "A", "IMG")
	  # "<BR>&lt;A HREF="url"&gt;&lt;/A&gt"

	print CGI::escapeElement("<BR><A HREF="url"></A>", ["A", "IMG"])
	  # "<BR>&lt;A HREF="url"&gt;&lt;/A&gt"
=end
  def CGI::escapeElement(string, *element)
    string.gsub(/<\/?(?:#{element.join("|")})(?!\w)(?:.|\n)*?>/ni) do
      CGI::escapeHTML($&)
    end
  end


=begin
=== UNESCAPE ELEMENT
	print CGI::unescapeElement(
	        CGI::escapeHTML("<BR><A HREF="url"></A>"), "A", "IMG")
	  # "&lt;BR&gt;<A HREF="url"></A>"

	print CGI::unescapeElement(
	        CGI::escapeHTML("<BR><A HREF="url"></A>"), ["A", "IMG"])
	  # "&lt;BR&gt;<A HREF="url"></A>"
=end
  def CGI::unescapeElement(string, *element)
    string.gsub(/&lt;\/?(?:#{element.join("|")})(?!\w)(?:.|\n)*?&gt;/ni) do
      CGI::unescapeHTML($&)
    end
  end


=begin
=== MAKE RFC1123 DATE STRING
	CGI::rfc1123_date(Time.now)
	  # Sut, 1 Jan 2000 00:00:00 GMT
=end
  def CGI::rfc1123_date(time)
    t = time.clone.gmtime
    return format("%s, %.2d %s %d %.2d:%.2d:%.2d GMT",
                RFC822_DAYS[t.wday], t.day, RFC822_MONTHS[t.month-1], t.year,
                t.hour, t.min, t.sec)
  end


=begin
=== MAKE HTTP HEADER STRING
	header
	  # Content-Type: text/html

	header("text/plain")
	  # Content-Type: text/plain

	header({"nph"        => true,
	        "status"     => "OK",  # == "200 OK"
	          # "status"     => "200 GOOD",
	        "server"     => ENV['SERVER_SOFTWARE'],
	        "connection" => "close",
	        "type"       => "text/html",
	        "charset"    => "iso-2022-jp",
	          # Content-Type: text/html; charset=iso-2022-jp
	        "language"   => "ja",
	        "expires"    => Time.now + 30,
	        "cookie"     => [cookie1, cookie2],
	        "my_header1" => "my_value"
	        "my_header2" => "my_value"})

header will not convert charset.

status:
	"OK"                  --> "200 OK"
	"PARTIAL_CONTENT"     --> "206 Partial Content"
	"MULTIPLE_CHOICES"    --> "300 Multiple Choices"
	"MOVED"               --> "301 Moved Permanently"
	"REDIRECT"            --> "302 Found"
	"NOT_MODIFIED"        --> "304 Not Modified"
	"BAD_REQUEST"         --> "400 Bad Request"
	"AUTH_REQUIRED"       --> "401 Authorization Required"
	"FORBIDDEN"           --> "403 Forbidden"
	"NOT_FOUND"           --> "404 Not Found"
	"METHOD_NOT_ALLOWED"  --> "405 Method Not Allowed"
	"NOT_ACCEPTABLE"      --> "406 Not Acceptable"
	"LENGTH_REQUIRED"     --> "411 Length Required"
	"PRECONDITION_FAILED" --> "412 Rrecondition Failed"
	"SERVER_ERROR"        --> "500 Internal Server Error"
	"NOT_IMPLEMENTED"     --> "501 Method Not Implemented"
	"BAD_GATEWAY"         --> "502 Bad Gateway"
	"VARIANT_ALSO_VARIES" --> "506 Variant Also Negotiates"

=end
  def header(options = "text/html")

    buf = ""

    if options.kind_of?(String)
      options = { "type" => options }
    end

    unless options.has_key?("type")
      options["type"] = "text/html"
    end

    if options.has_key?("charset")
      options["type"].concat( "; charset=" )
      options["type"].concat( options.delete("charset") )
    end

    if options.delete("nph") or (/IIS/n === env_table['SERVER_SOFTWARE'])
      buf.concat( (env_table["SERVER_PROTOCOL"] or "HTTP/1.0")  + " " )
      buf.concat( (HTTP_STATUS[options["status"]] or
                      options["status"] or
                      "200 OK"
                     ) + EOL
      )
      buf.concat(
        "Date: " + CGI::rfc1123_date(Time.now) + EOL
      )

      unless options.has_key?("server")
        options["server"] = (env_table['SERVER_SOFTWARE'] or "")
      end

      unless options.has_key?("connection")
        options["connection"] = "close"
      end

    end
    options.delete("status")

    if options.has_key?("server")
      buf.concat("Server: " + options.delete("server") + EOL)
    end

    if options.has_key?("connection")
      buf.concat("Connection: " + options.delete("connection") + EOL)
    end

    buf.concat("Content-Type: " + options.delete("type") + EOL)

    if options.has_key?("length")
      buf.concat("Content-Length: " + options.delete("length").to_s + EOL)
    end

    if options.has_key?("language")
      buf.concat("Content-Language: " + options.delete("language") + EOL)
    end

    if options.has_key?("expires")
      buf.concat("Expires: " + CGI::rfc1123_date( options.delete("expires") ) + EOL)
    end

    if options.has_key?("cookie")
      if options["cookie"].kind_of?(String) or
           options["cookie"].kind_of?(Cookie)
        buf.concat("Set-Cookie: " + options.delete("cookie").to_s + EOL)
      elsif options["cookie"].kind_of?(Array)
        options.delete("cookie").each{|cookie|
          buf.concat("Set-Cookie: " + cookie.to_s + EOL)
        }
      elsif options["cookie"].kind_of?(Hash)
        options.delete("cookie").each_value{|cookie|
          buf.concat("Set-Cookie: " + cookie.to_s + EOL)
        }
      end
    end
    if @output_cookies
      for cookie in @output_cookies
	buf.concat("Set-Cookie: " + cookie.to_s + EOL)
      end
    end

    options.each{|key, value|
      buf.concat(key + ": " + value + EOL)
    }

    if defined?(MOD_RUBY)
      buf.scan(/([^:]+): (.+)#{EOL}/n){
        Apache::request[$1] = $2
      }
      Apache::request.send_http_header
      ''
    else
      buf + EOL
    end

  end # header()


=begin
=== PRINT HTTP HEADER AND STRING TO $DEFAULT_OUTPUT ($>)
	cgi = CGI.new
	cgi.out{ "string" }
	  # Content-Type: text/html
	  # Content-Length: 6
	  #
	  # string

	cgi.out("text/plain"){ "string" }
	  # Content-Type: text/plain
	  # Content-Length: 6
	  #
	  # string

	cgi.out({"nph"        => true,
	         "status"     => "OK",  # == "200 OK"
	         "server"     => ENV['SERVER_SOFTWARE'],
	         "connection" => "close",
	         "type"       => "text/html",
	         "charset"    => "iso-2022-jp",
	           # Content-Type: text/html; charset=iso-2022-jp
	         "language"   => "ja",
	         "expires"    => Time.now + (3600 * 24 * 30),
	         "cookie"     => [cookie1, cookie2],
	         "my_header1" => "my_value",
	         "my_header2" => "my_value"}){ "string" }

if "HEAD" == REQUEST_METHOD then output only HTTP header.

if charset is "iso-2022-jp" or "euc-jp" or "shift_jis" then
convert string charset, and set language to "ja".

=end
  def out(options = "text/html")

    options = { "type" => options } if options.kind_of?(String)
    content = yield

    if options.has_key?("charset")
      require "nkf"
      case options["charset"]
      when /iso-2022-jp/ni
        content = NKF::nkf('-j', content)
        options["language"] = "ja" unless options.has_key?("language")
      when /euc-jp/ni
        content = NKF::nkf('-e', content)
        options["language"] = "ja" unless options.has_key?("language")
      when /shift_jis/ni
        content = NKF::nkf('-s', content)
        options["language"] = "ja" unless options.has_key?("language")
      end
    end

    options["length"] = content.length.to_s
    output = stdoutput
    output.binmode if defined? output.binmode
    output.print header(options)
    output.print content unless "HEAD" == env_table['REQUEST_METHOD']
  end


=begin
=== PRINT
	cgi = CGI.new
	cgi.print    # default:  cgi.print == $DEFAULT_OUTPUT.print
=end
  def print(*options)
    stdoutput.print(*options)
  end


=begin
=== MAKE COOKIE OBJECT
	cookie1 = CGI::Cookie::new("name", "value1", "value2", ...)
	cookie1 = CGI::Cookie::new({"name" => "name", "value" => "value"})
	cookie1 = CGI::Cookie::new({'name'    => 'name',
	                            'value'   => ['value1', 'value2', ...],
	                            'path'    => 'path',   # optional
	                            'domain'  => 'domain', # optional
	                            'expires' => Time.now, # optional
	                            'secure'  => true      # optional
	                           })

	cgi.out({"cookie" => [cookie1, cookie2]}){ "string" }

	name    = cookie1.name
	values  = cookie1.value
	path    = cookie1.path
	domain  = cookie1.domain
	expires = cookie1.expires
	secure  = cookie1.secure

	cookie1.name    = 'name'
	cookie1.value   = ['value1', 'value2', ...]
	cookie1.path    = 'path'
	cookie1.domain  = 'domain'
	cookie1.expires = Time.now + 30
	cookie1.secure  = true
=end
  require "delegate"
  class Cookie < SimpleDelegator

    def initialize(name = "", *value)
      options = if name.kind_of?(String)
                  { "name" => name, "value" => value }
                else
                  name
                end
      unless options.has_key?("name")
        raise ArgumentError, "`name' required"
      end

      @name = options["name"]
      @value = Array(options["value"])
      # simple support for IE
      if options["path"]
        @path = options["path"]
      elsif ENV["REQUEST_URI"]
        @path = ENV["REQUEST_URI"].sub(/\?.*/n,'')
        if ENV["PATH_INFO"]
          @path = @path[0...@path.rindex(ENV["PATH_INFO"])]
        end
      else
        @path = (ENV["SCRIPT_NAME"] or "")
      end
      @domain = options["domain"]
      @expires = options["expires"]
      @secure = options["secure"] == true ? true : false

      super(@value)
    end

    attr_accessor("name", "value", "path", "domain", "expires")
    attr_reader("secure")
    def secure=(val)
      @secure = val if val == true or val == false
      @secure
    end

    def to_s
      buf = ""
      buf.concat(@name + '=')

      if @value.kind_of?(String)
        buf.concat CGI::escape(@value)
      else
        buf.concat(@value.collect{|v| CGI::escape(v) }.join("&"))
      end

      if @domain
        buf.concat('; domain=' + @domain)
      end

      if @path
        buf.concat('; path=' + @path)
      end

      if @expires
        buf.concat('; expires=' + CGI::rfc1123_date(@expires))
      end

      if @secure == true
        buf.concat('; secure')
      end

      buf
    end

  end # class Cookie


=begin
=== PARSE RAW COOKIE STRING
	cookies = CGI::Cookie::parse("raw_cookie_string")
	  # { "name1" => cookie1, "name2" => cookie2, ... }
=end
  def Cookie::parse(raw_cookie)
    cookies = Hash.new([])
    return cookies unless raw_cookie

    raw_cookie.split('; ').each do |pairs|
      name, values = pairs.split('=',2)
      name = CGI::unescape(name)
      values ||= ""
      values = values.split('&').collect{|v| CGI::unescape(v) }
      if cookies.has_key?(name)
        cookies[name].value.push(*values)
      else
        cookies[name] = Cookie::new({ "name" => name, "value" => values })
      end
    end

    cookies
  end


=begin
=== PARSE QUERY STRING
	params = CGI::parse("query_string")
	  # {"name1" => ["value1", "value2", ...],
	  #  "name2" => ["value1", "value2", ...], ... }
=end
  def CGI::parse(query)
    params = Hash.new([])

    query.split(/[&;]/n).each do |pairs|
      key, value = pairs.split('=',2).collect{|v| CGI::unescape(v) }
      if params.has_key?(key)
        params[key].push(value)
      else
        params[key] = [value]
      end
    end

    params
  end


  module QueryExtension

    for env in %w[ CONTENT_LENGTH SERVER_PORT ]
      eval( <<-END )
        def #{env.sub(/^HTTP_/n, '').downcase}
          env_table["#{env}"] && Integer(env_table["#{env}"])
        end
      END
    end

    for env in %w[ AUTH_TYPE CONTENT_TYPE GATEWAY_INTERFACE PATH_INFO
        PATH_TRANSLATED QUERY_STRING REMOTE_ADDR REMOTE_HOST
        REMOTE_IDENT REMOTE_USER REQUEST_METHOD SCRIPT_NAME
        SERVER_NAME SERVER_PROTOCOL SERVER_SOFTWARE

        HTTP_ACCEPT HTTP_ACCEPT_CHARSET HTTP_ACCEPT_ENCODING
        HTTP_ACCEPT_LANGUAGE HTTP_CACHE_CONTROL HTTP_FROM HTTP_HOST
        HTTP_NEGOTIATE HTTP_PRAGMA HTTP_REFERER HTTP_USER_AGENT ]
      eval( <<-END )
        def #{env.sub(/^HTTP_/n, '').downcase}
          env_table["#{env}"]
        end
      END
    end

    def raw_cookie
      env_table["HTTP_COOKIE"]
    end

    def raw_cookie2
      env_table["HTTP_COOKIE2"]
    end

    attr_accessor("cookies")
    attr("params")
    def params=(hash)
      @params.clear
      @params.update(hash)
    end

    def read_multipart(boundary, content_length)
      params = Hash.new([])
      boundary = "--" + boundary
      buf = ""
      bufsize = 10 * 1024

      # start multipart/form-data
      stdinput.binmode
      boundary_size = boundary.size + EOL.size
      content_length -= boundary_size
      status = stdinput.read(boundary_size)
      if nil == status
        raise EOFError, "no content body"
      end

      require "tempfile"

      until -1 == content_length
        head = nil
        body = Tempfile.new("CGI")
        body.binmode

        until head and (/#{boundary}(?:#{EOL}|--)/n === buf)

          if (not head) and (/#{EOL}#{EOL}/n === buf)
            buf = buf.sub(/\A((?:.|\n)*?#{EOL})#{EOL}/n) do
              head = $1.dup
              ""
            end
            next
          end

          if head and ( (EOL + boundary + EOL).size < buf.size )
            body.print buf[0 ... (buf.size - (EOL + boundary + EOL).size)]
            buf[0 ... (buf.size - (EOL + boundary + EOL).size)] = ""
          end

          c = if bufsize < content_length
                stdinput.read(bufsize) or ''
              else
                stdinput.read(content_length) or ''
              end
          buf.concat c
          content_length -= c.size

        end

        buf = buf.sub(/\A((?:.|\n)*?)(?:#{EOL})?#{boundary}(#{EOL}|--)/n) do
          body.print $1
          if "--" == $2
            content_length = -1
          end
          ""
        end

        body.rewind

        eval <<-END
          def body.local_path
            #{body.path.dump}
          end
        END

        /Content-Disposition:.* filename="?([^\";]*)"?/ni === head
        eval <<-END
          def body.original_filename
            #{
              filename = ($1 or "").dup
              if (/Mac/ni === env_table['HTTP_USER_AGENT']) and
                 (/Mozilla/ni === env_table['HTTP_USER_AGENT']) and
                 (not /MSIE/ni === env_table['HTTP_USER_AGENT'])
                CGI::unescape(filename)
              else
                filename
              end.dump
            }
          end
        END

        /Content-Type: (.*)/ni === head
        eval <<-END
          def body.content_type
            #{($1 or "").dump}
          end
        END

        /Content-Disposition:.* name="?([^\";]*)"?/ni === head
        name = $1.dup

        if params.has_key?(name)
          params[name].push(body)
        else
          params[name] = [body]
        end

      end

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
        readlines.join(' ').gsub(/\n/n, '')
      end.gsub(/\\=/n, '%3D').gsub(/\\&/n, '%26')

      words = Shellwords.shellwords(string)

      if words.find{|x| /=/n === x }
        words.join('&')
      else
        words.join('+')
      end
    end
    private :read_from_cmdline

    def initialize_query()
      if ("POST" == env_table['REQUEST_METHOD']) and
         (%r|\Amultipart/form-data.*boundary=\"?([^\";,]+)\"?|n ===
           env_table['CONTENT_TYPE'])
        boundary = $1.dup
        @params = read_multipart(boundary, Integer(env_table['CONTENT_LENGTH']))
      else
        @params = CGI::parse(
                    case env_table['REQUEST_METHOD']
                    when "GET", "HEAD"
                      if defined?(MOD_RUBY)
                        Apache::request.args or ""
                      else
                        env_table['QUERY_STRING'] or ""
                      end
                    when "POST"
                      stdinput.binmode
                      stdinput.read(Integer(env_table['CONTENT_LENGTH'])) or ''
                    else
                      read_from_cmdline
                    end
                  )
      end

      @cookies = CGI::Cookie::parse((env_table['HTTP_COOKIE'] or env_table['COOKIE']))

    end
    private :initialize_query

    def [](*args)
      @params[*args]
    end

    def keys(*args)
      @params.keys(*args)
    end

    def has_key?(*args)
      @params.has_key?(*args)
    end
    alias key? has_key?
    alias include? has_key?

  end # QueryExtension


=begin
=== HTML PRETTY FORMAT
	print CGI::pretty("<HTML><BODY></BODY></HTML>")
	  # <HTML>
	  #   <BODY>
	  #   </BODY>
	  # </HTML>

	print CGI::pretty("<HTML><BODY></BODY></HTML>", "\t")
	  # <HTML>
	  # 	<BODY>
	  # 	</BODY>
	  # </HTML>
=end
  def CGI::pretty(string, shift = "  ")
    lines = string.gsub(/(?!\A)<(?:.|\n)*?>/n, "\n\\0").gsub(/<(?:.|\n)*?>(?!\n)/n, "\\0\n")
    end_pos = 0
    while end_pos = lines.index(/^<\/(\w+)/n, end_pos)
      element = $1.dup
      start_pos = lines.rindex(/^\s*<#{element}/ni, end_pos)
      lines[start_pos ... end_pos] = "__" + lines[start_pos ... end_pos].gsub(/\n(?!\z)/n, "\n" + shift) + "__"
    end
    lines.gsub(/^(\s*)__(?=<\/?\w)/n, '\1')
  end


=begin
== HTML ELEMENTS

	cgi = CGI.new("html3")  # add HTML generation methods
	cgi.element
	cgi.element{ "string" }
	cgi.element({ "ATTRILUTE1" => "value1", "ATTRIBUTE2" => "value2" })
	cgi.element({ "ATTRILUTE1" => "value1", "ATTRIBUTE2" => "value2" }){ "string" }

	# add HTML generation methods
	CGI.new("html3")    # html3.2
	CGI.new("html4")    # html4.0 (Strict)
	CGI.new("html4Tr")  # html4.0 Transitional
	CGI.new("html4Fr")  # html4.0 Frameset

=end


  module TagMaker

    # - -
    def nn_element_def(element)
      <<-END.gsub(/element\.downcase/n, element.downcase).gsub(/element\.upcase/n, element.upcase)
          "<element.upcase" + attributes.collect{|name, value|
            next unless value
            " " + CGI::escapeHTML(name) +
            if true == value
              ""
            else
              '="' + CGI::escapeHTML(value) + '"'
            end
          }.to_s + ">" +
          if iterator?
            yield.to_s
          else
            ""
          end +
          "</element.upcase>"
      END
    end

    # - O EMPTY
    def nOE_element_def(element)
      <<-END.gsub(/element\.downcase/n, element.downcase).gsub(/element\.upcase/n, element.upcase)
          "<element.upcase" + attributes.collect{|name, value|
            next unless value
            " " + CGI::escapeHTML(name) +
            if true == value
              ""
            else
              '="' + CGI::escapeHTML(value) + '"'
            end
          }.to_s + ">"
      END
    end

    # O O or - O
    def nO_element_def(element)
      <<-END.gsub(/element\.downcase/n, element.downcase).gsub(/element\.upcase/n, element.upcase)
          "<element.upcase" + attributes.collect{|name, value|
            next unless value
            " " + CGI::escapeHTML(name) +
            if true == value
              ""
            else
              '="' + CGI::escapeHTML(value) + '"'
            end
          }.to_s + ">" +
          if iterator?
            yield.to_s + "</element.upcase>"
          else
            ""
          end
      END
    end

  end # TagMaker


  module HtmlExtension


=begin
=== A ELEMENT
	a("url")
	  # = a({ "HREF" => "url" })
=end
    def a(href = "")
      attributes = if href.kind_of?(String)
                     { "HREF" => href }
                   else
                     href
                   end
      if iterator?
        super(attributes){ yield }
      else
        super(attributes)
      end
    end


=begin
=== BASE ELEMENT
	base("url")
	  # = base({ "HREF" => "url" })
=end
    def base(href = "")
      attributes = if href.kind_of?(String)
                     { "HREF" => href }
                   else
                     href
                   end
      if iterator?
        super(attributes){ yield }
      else
        super(attributes)
      end
    end


=begin
=== BLOCKQUOTE ELEMENT
	blockquote("url"){ "string" }
	  # = blockquote({ "CITE" => "url" }){ "string" }
=end
    def blockquote(cite = nil)
      attributes = if cite.kind_of?(String)
                     { "CITE" => cite }
                   else
                     cite or ""
                   end
      if iterator?
        super(attributes){ yield }
      else
        super(attributes)
      end
    end


=begin
=== CAPTION ELEMENT
	caption("align"){ "string" }
	  # = caption({ "ALIGN" => "align" }){ "string" }
=end
    def caption(align = nil)
      attributes = if align.kind_of?(String)
                     { "ALIGN" => align }
                   else
                     align or ""
                   end
      if iterator?
        super(attributes){ yield }
      else
        super(attributes)
      end
    end


=begin
=== CHECKBOX
	checkbox("name")
	  # = checkbox({ "NAME" => "name" })

	checkbox("name", "value")
	  # = checkbox({ "NAME" => "name", "VALUE" => "value" })

	checkbox("name", "value", true)
	  # = checkbox({ "NAME" => "name", "VALUE" => "value", "CHECKED" => true })
=end
    def checkbox(name = "", value = nil, checked = nil)
      attributes = if name.kind_of?(String)
                     { "TYPE" => "checkbox", "NAME" => name,
                       "VALUE" => value, "CHECKED" => checked }
                   else
                     name["TYPE"] = "checkbox"
                     name
                   end
      input(attributes)
    end


=begin
=== CHECKBOX_GROUP
	checkbox_group("name", "foo", "bar", "baz")
	  # <INPUT TYPE="checkbox" NAME="name" VALUE="foo">foo
	  # <INPUT TYPE="checkbox" NAME="name" VALUE="bar">bar
	  # <INPUT TYPE="checkbox" NAME="name" VALUE="baz">baz

	checkbox_group("name", ["foo"], ["bar", true], "baz")
	  # <INPUT TYPE="checkbox" NAME="name" VALUE="foo">foo
	  # <INPUT TYPE="checkbox" SELECTED NAME="name" VALUE="bar">bar
	  # <INPUT TYPE="checkbox" NAME="name" VALUE="baz">baz

	checkbox_group("name", ["1", "Foo"], ["2", "Bar", true], "Baz")
	  # <INPUT TYPE="checkbox" NAME="name" VALUE="1">Foo
	  # <INPUT TYPE="checkbox" SELECTED NAME="name" VALUE="2">Bar
	  # <INPUT TYPE="checkbox" NAME="name" VALUE="Baz">Baz

	checkbox_group({ "NAME" => "name",
	                 "VALUES" => ["foo", "bar", "baz"] })

	checkbox_group({ "NAME" => "name",
	                 "VALUES" => [["foo"], ["bar", true], "baz"] })

	checkbox_group({ "NAME" => "name",
	                 "VALUES" => [["1", "Foo"], ["2", "Bar", true], "Baz"] })
=end
    def checkbox_group(name = "", *values)
      if name.kind_of?(Hash)
        values = name["VALUES"]
        name = name["NAME"]
      end
      values.collect{|value|
        if value.kind_of?(String)
          checkbox(name, value) + value
        else
          if value[value.size - 1] == true
            checkbox(name, value[0], true) +
            value[value.size - 2]
          else
            checkbox(name, value[0]) +
            value[value.size - 1]
          end
        end
      }.to_s
    end


=begin
=== FILE_FIELD
	file_field("name")
	  # <INPUT TYPE="file" NAME="name" SIZE="20">

	file_field("name", 40)
	  # <INPUT TYPE="file" NAME="name" SIZE="40">

	file_field("name", 40, 100)
	  # <INPUT TYPE="file" NAME="name" SIZE="40", MAXLENGTH="100">

	file_field({ "NAME" => "name", "SIZE" => 40 })
	  # <INPUT TYPE="file" NAME="name" SIZE="40">
=end
    def file_field(name = "", size = 20, maxlength = nil)
      attributes = if name.kind_of?(String)
                     { "TYPE" => "file", "NAME" => name,
                       "SIZE" => size.to_s }
                   else
                     name["TYPE"] = "file"
                     name
                   end
      attributes["MAXLENGTH"] = maxlength.to_s if maxlength
      input(attributes)
    end


=begin
=== FORM ELEMENT
	form{ "string" }
	  # <FORM METHOD="post" ENCTYPE="application/x-www-form-urlencoded">string</FORM>

	form("get"){ "string" }
	  # <FORM METHOD="get" ENCTYPE="application/x-www-form-urlencoded">string</FORM>

	form("get", "url"){ "string" }
	  # <FORM METHOD="get" ACTION="url" ENCTYPE="application/x-www-form-urlencoded">string</FORM>

	form({"METHOD" => "post", ENCTYPE => "enctype"}){ "string" }
	  # <FORM METHOD="post" ENCTYPE="enctype">string</FORM>
=end
    def form(method = "post", action = nil, enctype = "application/x-www-form-urlencoded")
      attributes = if method.kind_of?(String)
                     { "METHOD" => method, "ACTION" => action,
                       "ENCTYPE" => enctype } 
                   else
                     unless method.has_key?("METHOD")
                       method["METHOD"] = method
                     end
                     unless method.has_key?("ENCTYPE")
                       method["ENCTYPE"] = enctype
                     end
                     method
                   end
      if iterator?
	body = yield
      else
        body = ""
      end
      if @output_hidden
	hidden = @output_hidden.collect{|k,v|
	  "<INPUT TYPE=HIDDEN NAME=\"#{k}\" VALUE=\"#{v}\">"
	}.to_s
	body.concat hidden
      end
      super(attributes){body}
    end

=begin
=== HIDDEN FIELD
	hidden("name")
	  # <INPUT TYPE="hidden" NAME="name">

	hidden("name", "value")
	  # <INPUT TYPE="hidden" NAME="name" VALUE="value">

	hidden({ "NAME" => "name", "VALUE" => "reset", "ID" => "foo" })
	  # <INPUT TYPE="hidden" NAME="name" VALUE="value" ID="foo">
=end
    def hidden(name = "", value = nil)
      attributes = if name.kind_of?(String)
                     { "TYPE" => "hidden", "NAME" => name, "VALUE" => value }
                   else
                     name["TYPE"] = "hidden"
                     name
                   end
      input(attributes)
    end


=begin
=== HTML ELEMENT

	html{ "string" }
	  # <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN"><HTML>string</HTML>

	html({ "LANG" => "ja" }){ "string" }
	  # <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN"><HTML LANG="ja">string</HTML>

	html({ "DOCTYPE" => false }){ "string" }
	  # <HTML>string</HTML>

	html({ "DOCTYPE" => '<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">' }){ "string" }
	  # <!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN"><HTML>string</HTML>

	html({ "PRETTY" => "  " }){ "<BODY></BODY>" }
	  # <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
	  # <HTML>
	  #   <BODY>
	  #   </BODY>
	  # </HTML>

	html({ "PRETTY" => "\t" }){ "<BODY></BODY>" }
	  # <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
	  # <HTML>
	  # 	<BODY>
	  # 	</BODY>
	  # </HTML>

	html("PRETTY"){ "<BODY></BODY>" }
	  # = html({ "PRETTY" => "  " }){ "<BODY></BODY>" }

	html(if $VERBOSE then "PRETTY" end){ "HTML string" }

=end
    def html(attributes = {})
      if nil == attributes
        attributes = {}
      elsif "PRETTY" == attributes
        attributes = { "PRETTY" => true }
      end
      pretty = attributes.delete("PRETTY")
      buf = ""

      if attributes.has_key?("DOCTYPE")
        if attributes["DOCTYPE"]
          buf.concat( attributes.delete("DOCTYPE") )
        else
          attributes.delete("DOCTYPE")
        end
      else
        buf.concat( doctype )
      end

      if iterator?
        buf.concat( super(attributes){ yield } )
      else
        buf.concat( super(attributes) )
      end

      if pretty
        CGI::pretty(buf, pretty)
      else
        buf
      end

    end


=begin
=== IMAGE_BUTTON
	image_button("url")
	  # <INPUT TYPE="image" SRC="url">

	image_button("url", "name", "string")
	  # <INPUT TYPE="image" SRC="url" NAME="name", ALT="string">

	image_button({ "SRC" => "url", "ATL" => "strng" })
	  # <INPUT TYPE="image" SRC="url" ALT="string">
=end
    def image_button(src = "", name = nil, alt = nil)
      attributes = if src.kind_of?(String)
                     { "TYPE" => "image", "SRC" => src, "NAME" => name,
                       "ALT" => alt }
                   else
                     src["TYPE"] = "image"
                     src["SRC"] ||= ""
                     src
                   end
      input(attributes)
    end


=begin
=== IMG ELEMENT
	img("src", "alt", 100, 50)
	  # <IMG SRC="src" ALT="alt" WIDTH="100", HEIGHT="50">

	img({ "SRC" => "src", "ALT" => "alt", "WIDTH" => 100, "HEIGHT" => 50 })
	  # <IMG SRC="src" ALT="alt" WIDTH="100", HEIGHT="50">
=end
    def img(src = "", alt = "", width = nil, height = nil)
      attributes = if src.kind_of?(String)
                     { "SRC" => src, "ALT" => alt }
                   else
                     src
                   end
      attributes["WIDTH"] = width.to_s if width
      attributes["HEIGHT"] = height.to_s if height
      super(attributes)
    end


=begin
=== MULTIPART FORM
	multipart_form{ "string" }
	  # <FORM METHOD="post" ENCTYPE="multipart/form-data">string</FORM>

	multipart_form("url"){ "string" }
	  # <FORM METHOD="post" ACTION="url" ENCTYPE="multipart/form-data">string</FORM>
=end
    def multipart_form(action = nil, enctype = "multipart/form-data")
      attributes = if action == nil
                     { "METHOD" => "post", "ENCTYPE" => enctype } 
                   elsif action.kind_of?(String)
                     { "METHOD" => "post", "ACTION" => action,
                       "ENCTYPE" => enctype } 
                   else
                     unless action.has_key?("METHOD")
                       action["METHOD"] = "post"
                     end
                     unless action.has_key?("ENCTYPE")
                       action["ENCTYPE"] = enctype
                     end
                     action
                   end
      if iterator?
        form(attributes){ yield }
      else
        form(attributes)
      end
    end


=begin
=== PASSWORD_FIELD
	password_field("name")
	  # <INPUT TYPE="password" NAME="name" SIZE="40">

	password_field("name", "value")
	  # <INPUT TYPE="password" NAME="name" VALUE="value" SIZE="40">

	password_field("password", "value", 80, 200)
	  # <INPUT TYPE="password" NAME="name" VALUE="value", SIZE="80", MAXLENGTH="200">

	password_field({ "NAME" => "name", "VALUE" => "value" })
	  # <INPUT TYPE="password" NAME="name" VALUE="value">
=end
    def password_field(name = "", value = nil, size = 40, maxlength = nil)
      attributes = if name.kind_of?(String)
                     { "TYPE" => "password", "NAME" => name,
                       "VALUE" => value, "SIZE" => size.to_s }
                   else
                     name["TYPE"] = "password"
                     name
                   end
      attributes["MAXLENGTH"] = maxlength.to_s if maxlength
      input(attributes)
    end


=begin
=== POPUP_MENU
	popup_menu("name", "foo", "bar", "baz")
	  # <SELECT NAME="name">
	  #   <OPTION VALUE="foo">foo</OPTION>
	  #   <OPTION VALUE="bar">bar</OPTION>
	  #   <OPTION VALUE="baz">baz</OPTION>
	  # </SELECT>

	popup_menu("name", ["foo"], ["bar", true], "baz")
	  # <SELECT NAME="name">
	  #   <OPTION VALUE="foo">foo</OPTION>
	  #   <OPTION VALUE="bar" SELECTED>bar</OPTION>
	  #   <OPTION VALUE="baz">baz</OPTION>
	  # </SELECT>

	popup_menu("name", ["1", "Foo"], ["2", "Bar", true], "Baz")
	  # <SELECT NAME="name">
	  #   <OPTION VALUE="1">Foo</OPTION>
	  #   <OPTION SELECTED VALUE="2">Bar</OPTION>
	  #   <OPTION VALUE="Baz">Baz</OPTION>
	  # </SELECT>

	popup_menu({"NAME" => "name", "SIZE" => 2, "MULTIPLE" => true,
	            "VALUES" => [["1", "Foo"], ["2", "Bar", true], "Baz"] })
	  # <SELECT NAME="name" MULTIPLE SIZE="2">
	  #   <OPTION VALUE="1">Foo</OPTION>
	  #   <OPTION SELECTED VALUE="2">Bar</OPTION>
	  #   <OPTION VALUE="Baz">Baz</OPTION>
	  # </SELECT>
=end
    def popup_menu(name = "", *values)

      if name.kind_of?(Hash)
        values   = name["VALUES"]
        size     = name["SIZE"].to_s if name["SIZE"]
        multiple = name["MULTIPLE"]
        name     = name["NAME"]
      else
        size = nil
        multiple = nil
      end

      select({ "NAME" => name, "SIZE" => size,
               "MULTIPLE" => multiple }){
        values.collect{|value|
          if value.kind_of?(String)
            option({ "VALUE" => value }){ value }
          else
            if value[value.size - 1] == true
              option({ "VALUE" => value[0], "SELECTED" => true }){
                value[value.size - 2]
              }
            else
              option({ "VALUE" => value[0] }){
                value[value.size - 1]
              }
            end
          end
        }.to_s
      }

    end


=begin
=== RADIO_BUTTON
	radio_button("name", "value")
	  # <INPUT TYPE="radio" NAME="name", VALUE="value">

	radio_button("name", "value", true)
	  # <INPUT TYPE="radio" NAME="name", VALUE="value", CHECKED>

	radio_button({ "NAME" => "name", "VALUE" => "value", "ID" => "foo" })
	  # <INPUT TYPE="radio" NAME="name" VALUE="value" ID="foo">
=end
    def radio_button(name = "", value = nil, checked = nil)
      attributes = if name.kind_of?(String)
                     { "TYPE" => "radio", "NAME" => name,
                       "VALUE" => value, "CHECKED" => checked }
                   else
                     name["TYPE"] = "radio"
                     name
                   end
      input(attributes)
    end


=begin
=== RADIO_GROUP
	radio_group("name", "foo", "bar", "baz")
	  # <INPUT TYPE="radio" NAME="name" VALUE="foo">foo
	  # <INPUT TYPE="radio" NAME="name" VALUE="bar">bar
	  # <INPUT TYPE="radio" NAME="name" VALUE="baz">baz

	radio_group("name", ["foo"], ["bar", true], "baz")
	  # <INPUT TYPE="radio" NAME="name" VALUE="foo">foo
	  # <INPUT TYPE="radio" SELECTED NAME="name" VALUE="bar">bar
	  # <INPUT TYPE="radio" NAME="name" VALUE="baz">baz

	radio_group("name", ["1", "Foo"], ["2", "Bar", true], "Baz")
	  # <INPUT TYPE="radio" NAME="name" VALUE="1">Foo
	  # <INPUT TYPE="radio" SELECTED NAME="name" VALUE="2">Bar
	  # <INPUT TYPE="radio" NAME="name" VALUE="Baz">Baz

	radio_group({ "NAME" => "name",
	              "VALUES" => ["foo", "bar", "baz"] })

	radio_group({ "NAME" => "name",
	              "VALUES" => [["foo"], ["bar", true], "baz"] })

	radio_group({ "NAME" => "name",
	              "VALUES" => [["1", "Foo"], ["2", "Bar", true], "Baz"] })
=end
    def radio_group(name = "", *values)
      if name.kind_of?(Hash)
        values = name["VALUES"]
        name = name["NAME"]
      end
      values.collect{|value|
        if value.kind_of?(String)
          radio_button(name, value) + value
        else
          if value[value.size - 1] == true
            radio_button(name, value[0], true) +
            value[value.size - 2]
          else
            radio_button(name, value[0]) +
            value[value.size - 1]
          end
        end
      }.to_s
    end


=begin
=== RESET BUTTON
	reset
	  # <INPUT TYPE="reset">

	reset("reset")
	  # <INPUT TYPE="reset" VALUE="reset">

	reset({ "VALUE" => "reset", "ID" => "foo" })
	  # <INPUT TYPE="reset" VALUE="reset" ID="foo">
=end
    def reset(value = nil, name = nil)
      attributes = if (not value) or value.kind_of?(String)
                     { "TYPE" => "reset", "VALUE" => value, "NAME" => name }
                   else
                     value["TYPE"] = "reset"
                     value
                   end
      input(attributes)
    end


=begin
=== SCROLLING_LIST
	scrolling_list({"NAME" => "name", "SIZE" => 2, "MULTIPLE" => true,
	                "VALUES" => [["1", "Foo"], ["2", "Bar", true], "Baz"] })
	  # <SELECT NAME="name" MULTIPLE SIZE="2">
	  #   <OPTION VALUE="1">Foo</OPTION>
	  #   <OPTION SELECTED VALUE="2">Bar</OPTION>
	  #   <OPTION VALUE="Baz">Baz</OPTION>
	  # </SELECT>
=end
    alias scrolling_list popup_menu


=begin
=== SUBMIT BUTTON
	submit
	  # <INPUT TYPE="submit">

	submit("ok")
	  # <INPUT TYPE="submit" VALUE="ok">

	submit("ok", "button1")
	  # <INPUT TYPE="submit" VALUE="ok" NAME="button1">

	submit({ "VALUE" => "ok", "NAME" => "button1", "ID" => "foo" })
	  # <INPUT TYPE="submit" VALUE="ok" NAME="button1" ID="foo">
=end
    def submit(value = nil, name = nil)
      attributes = if (not value) or value.kind_of?(String)
                     { "TYPE" => "submit", "VALUE" => value, "NAME" => name }
                   else
                     value["TYPE"] = "submit"
                     value
                   end
      input(attributes)
    end


=begin
=== TEXT_FIELD
	text_field("name")
	  # <INPUT TYPE="text" NAME="name" SIZE="40">

	text_field("name", "value")
	  # <INPUT TYPE="text" NAME="name" VALUE="value" SIZE="40">

	text_field("name", "value", 80)
	  # <INPUT TYPE="text" NAME="name" VALUE="value", SIZE="80">

	text_field("name", "value", 80, 200)
	  # <INPUT TYPE="text" NAME="name" VALUE="value", SIZE="80", MAXLENGTH="200">

	text_field({ "NAME" => "name", "VALUE" => "value" })
	  # <INPUT TYPE="text" NAME="name" VALUE="value">
=end
    def text_field(name = "", value = nil, size = 40, maxlength = nil)
      attributes = if name.kind_of?(String)
                     { "TYPE" => "text", "NAME" => name, "VALUE" => value,
                       "SIZE" => size.to_s }
                   else
                     name["TYPE"] = "text"
                     name
                   end
      attributes["MAXLENGTH"] = maxlength.to_s if maxlength
      input(attributes)
    end


=begin
=== TEXTAREA ELEMENT

	textarea("name")
	  # = textarea({ "NAME" => "name", "COLS" => 70, "ROWS" => 10 })

	textarea("name", 40, 5)
	  # = textarea({ "NAME" => "name", "COLS" => 40, "ROWS" => 5 })
=end
    def textarea(name = "", cols = 70, rows = 10)
      attributes = if name.kind_of?(String)
                     { "NAME" => name, "COLS" => cols.to_s,
                       "ROWS" => rows.to_s }
                   else
                     name
                   end
      if iterator?
        super(attributes){ yield }
      else
        super(attributes)
      end
    end

  end # HtmlExtension


  module Html3

    def doctype
      %|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">|
    end

    def element_init
      extend TagMaker
      methods = ""
      # - -
      for element in %w[ A TT I B U STRIKE BIG SMALL SUB SUP EM STRONG
          DFN CODE SAMP KBD VAR CITE FONT ADDRESS DIV center MAP
          APPLET PRE XMP LISTING DL OL UL DIR MENU SELECT table TITLE
          STYLE SCRIPT H1 H2 H3 H4 H5 H6 TEXTAREA FORM BLOCKQUOTE
          CAPTION ]
        methods.concat( <<-BEGIN + nn_element_def(element) + <<-END )
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # - O EMPTY
      for element in %w[ IMG BASE BASEFONT BR AREA LINK PARAM HR INPUT
          ISINDEX META ]
        methods.concat( <<-BEGIN + nOE_element_def(element) + <<-END )
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # O O or - O
      for element in %w[ HTML HEAD BODY P PLAINTEXT DT DD LI OPTION tr
          th td ]
        methods.concat( <<-BEGIN + nO_element_def(element) + <<-END )
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end
      eval(methods)
    end

  end # Html3


  module Html4

    def doctype
      %|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0//EN" "http://www.w3.org/TR/REC-html40/strict.dtd">|
    end

    def element_init
      extend TagMaker
      methods = ""
      # - -
      for element in %w[ TT I B BIG SMALL EM STRONG DFN CODE SAMP KBD
        VAR CITE ABBR ACRONYM SUB SUP SPAN BDO ADDRESS DIV MAP OBJECT
        H1 H2 H3 H4 H5 H6 PRE Q INS DEL DL OL UL LABEL SELECT OPTGROUP
        FIELDSET LEGEND BUTTON TABLE TITLE STYLE SCRIPT NOSCRIPT
        TEXTAREA FORM A BLOCKQUOTE CAPTION ]
        methods.concat( <<-BEGIN + nn_element_def(element) + <<-END )
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # - O EMPTY
      for element in %w[ IMG BASE BR AREA LINK PARAM HR INPUT COL META ]
        methods.concat( <<-BEGIN + nOE_element_def(element) + <<-END )
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # O O or - O
      for element in %w[ HTML BODY P DT DD LI OPTION THEAD TFOOT TBODY
          COLGROUP TR TH TD HEAD]
        methods.concat( <<-BEGIN + nO_element_def(element) + <<-END )
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end
      eval(methods)
    end

  end # Html4


  module Html4Tr

    def doctype
      %|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN" "http://www.w3.org/TR/REC-html40/loose.dtd">|
    end

    def element_init
      extend TagMaker
      methods = ""
      # - -
      for element in %w[ TT I B U S STRIKE BIG SMALL EM STRONG DFN
          CODE SAMP KBD VAR CITE ABBR ACRONYM FONT SUB SUP SPAN BDO
          ADDRESS DIV CENTER MAP OBJECT APPLET H1 H2 H3 H4 H5 H6 PRE Q
          INS DEL DL OL UL DIR MENU LABEL SELECT OPTGROUP FIELDSET
          LEGEND BUTTON TABLE IFRAME NOFRAMES TITLE STYLE SCRIPT
          NOSCRIPT TEXTAREA FORM A BLOCKQUOTE CAPTION ]
        methods.concat( <<-BEGIN + nn_element_def(element) + <<-END )
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # - O EMPTY
      for element in %w[ IMG BASE BASEFONT BR AREA LINK PARAM HR INPUT
          COL ISINDEX META ]
        methods.concat( <<-BEGIN + nOE_element_def(element) + <<-END )
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # O O or - O
      for element in %w[ HTML BODY P DT DD LI OPTION THEAD TFOOT TBODY
          COLGROUP TR TH TD HEAD ]
        methods.concat( <<-BEGIN + nO_element_def(element) + <<-END )
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end
      eval(methods)
    end

  end # Html4Tr


  module Html4Fr

    def doctype
      %|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Frameset//EN" "http://www.w3.org/TR/REC-html40/frameset.dtd">|
    end

    def element_init
      extend TagMaker
      extend Html4Tr
      element_init()
      methods = ""
      # - -
      for element in %w[ FRAMESET ]
        methods.concat( <<-BEGIN + nn_element_def(element) + <<-END )
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # - O EMPTY
      for element in %w[ FRAME ]
        methods.concat( <<-BEGIN + nOE_element_def(element) + <<-END )
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end
      eval(methods)
    end

  end # Html4Fr


  def initialize(type = "query")
    extend QueryExtension
    if defined?(CGI_PARAMS)
      @params  = CGI_PARAMS.nil?  ? nil : CGI_PARAMS.dup
      @cookies = CGI_COOKIES.nil? ? nil : CGI_COOKIES.dup
    else
      initialize_query()  # set @params, @cookies
      eval "CGI_PARAMS  = @params.nil?  ? nil : @params.dup"
      eval "CGI_COOKIES = @cookies.nil? ? nil : @cookies.dup"
    end
    @output_cookies = nil
    @output_hidden = nil

    case type
    when "html3"
      extend Html3
      element_init()
      extend HtmlExtension
    when "html4"
      extend Html4
      element_init()
      extend HtmlExtension
    when "html4Tr"
      extend Html4Tr
      element_init()
      extend HtmlExtension
    when "html4Fr"
      extend Html4Fr
      element_init()
      extend HtmlExtension
    end

  end

  if defined?(MOD_RUBY) and (RUBY_VERSION < "1.4.3")
    raise "Please, use ruby1.4.3 or later."
  else
    at_exit() do
      if defined?(CGI_PARAMS)
        remove_const(:CGI_PARAMS)
        remove_const(:CGI_COOKIES)
      end
    end
  end
end


=begin

== HISTORY

=== Version 1.61 - wakou

2000/06/13 15:49:27

- read_multipart(): if no content body then raise EOFError.

=== Version 1.60 - wakou

2000/06/03 18:16:17

- improve: CGI::pretty()

=== Version 1.50 - wakou

2000/05/30 19:04:08

- CGI#out()
  if "HEAD" == REQUEST_METHOD then output only HTTP header.

=== Version 1.40 - wakou

2000/05/24 06:58:51

- typo: CGI::Cookie::new()
- bug fix: CGI::escape()
  bad: " " --> "%2B"  true: " " --> "+"
  thanks to Ryunosuke Ohshima <ryu@jaist.ac.jp>

=== Version 1.31 - wakou

2000/05/08 21:51:30

- improvement of time forming new CGI object accompanied with HTML generation methods.

=== Version 1.30 - wakou

2000/05/07 21:51:14

- require English.rb
- improvement of load time.

=== Version 1.21 - wakou

2000/05/02 21:44:12

- support for ruby 1.5.3 (2000-05-01) (Array#filter --> Array#collect!)

=== Version 1.20 - wakou

2000/04/03 18:31:42

- bug fix: CGI#image_button() can't get Hash option
  thanks to Takashi Ikeda <ikeda@auc.co.jp>
- CGI::unescapeHTML()
  simple support for "&#12345;"
- CGI::Cookie::new()
  simple support for IE
- CGI::escape()
  ' ' replaced by '+'

=== Version 1.10 - wakou

1999/12/06 20:16:34

- can make many CGI objects.
- if use mod_ruby, then require ruby1.4.3 or later.

=== Version 1.01 - wakou

1999/11/29 21:35:58

- support for ruby 1.5.0 (1999-11-20)

=== Version 1.00 - wakou

1999/09/13 23:00:58

- COUTION! name change. CGI.rb --> cgi.rb

- CGI#auth_type, CGI#content_length, CGI#content_type, ...
if not ENV included it, then return nil.

- CGI#content_length and CGI#server_port return Integer.

- if not CGI#params.include?('name'), then CGI#params['name'] return [].

- if not CGI#cookies.include?('name'), then CGI#cookies['name'] return [].

=== Version 0.41 - wakou

1999/08/05 18:04:59

- typo. thanks to MJ Ray <markj@altern.org>
	HTTP_STATUS["NOT_INPLEMENTED"] --> HTTP_STATUS["NOT_IMPLEMENTED"]

=== Version 0.40 - wakou

1999/07/20 20:44:31

- COUTION! incompatible change.
  sorry, but probably this change is last big incompatible change.

- CGI::print  -->  CGI#out

	cgi = CGI.new
	cgi.out{"string"}             # old: CGI::print{"string"}

- CGI::cookie  --> CGI::Cookie::new

	cookie1 = CGI::Cookie::new    # old: CGI::cookie

- CGI::header  -->  CGI#header

=== Version 0.30 - wakou

1999/06/29 06:50:21

- COUTION! incompatible change.
	query = CGI.new
	cookies = query.cookies       # old: query.cookie
	values = query.cookies[name]  # old: query.cookie[name]

=== Version 0.24 - wakou

1999/06/21 21:05:57

- CGI::Cookie::parse() return { name => CGI::Cookie object } pairs.

=== Version 0.23 - wakou

1999/06/20 23:29:12

- modified a bit to clear module separation.

=== Version 0.22 - matz

Mon Jun 14 17:49:32 JST 1999

- Cookies are now CGI::Cookie objects.
- Cookie modeled after CGI::Cookie.pm.

=== Version 0.21 - matz

Fri Jun 11 11:19:11 JST 1999

- modified a bit to clear module separation.

=== Version 0.20 - wakou

1999/06/03 06:48:15

- support for multipart form.

=== Version 0.10 - wakou

1999/05/24 07:05:41

- first release.

=end
