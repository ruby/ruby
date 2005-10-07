# 
# cgi.rb - cgi support library
# 
# Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
# 
# Copyright (C) 2000  Information-technology Promotion Agency, Japan
#
# Author: Wakou Aoyama <wakou@ruby-lang.org>
#
# Documentation: Wakou Aoyama (RDoc'd and embellished by William Webber) 
# 
# == Overview
#
# The Common Gateway Interface (CGI) is a simple protocol
# for passing an HTTP request from a web server to a
# standalone program, and returning the output to the web
# browser.  Basically, a CGI program is called with the
# parameters of the request passed in either in the
# environment (GET) or via $stdin (POST), and everything
# it prints to $stdout is returned to the client.
# 
# This file holds the +CGI+ class.  This class provides
# functionality for retrieving HTTP request parameters,
# managing cookies, and generating HTML output.  See the
# class documentation for more details and examples of use.
#
# The file cgi/session.rb provides session management
# functionality; see that file for more details.
#
# See http://www.w3.org/CGI/ for more information on the CGI
# protocol.

raise "Please, use ruby 1.5.4 or later." if RUBY_VERSION < "1.5.4"

require 'English'

# CGI class.  See documentation for the file cgi.rb for an overview
# of the CGI protocol.
#
# == Introduction
#
# CGI is a large class, providing several categories of methods, many of which
# are mixed in from other modules.  Some of the documentation is in this class,
# some in the modules CGI::QueryExtension and CGI::HtmlExtension.  See
# CGI::Cookie for specific information on handling cookies, and cgi/session.rb
# (CGI::Session) for information on sessions.
#
# For queries, CGI provides methods to get at environmental variables,
# parameters, cookies, and multipart request data.  For responses, CGI provides
# methods for writing output and generating HTML.
#
# Read on for more details.  Examples are provided at the bottom.
#
# == Queries
#
# The CGI class dynamically mixes in parameter and cookie-parsing
# functionality,  environmental variable access, and support for
# parsing multipart requests (including uploaded files) from the
# CGI::QueryExtension module.
#
# === Environmental Variables
#
# The standard CGI environmental variables are available as read-only
# attributes of a CGI object.  The following is a list of these variables:
#
#
#   AUTH_TYPE               HTTP_HOST          REMOTE_IDENT
#   CONTENT_LENGTH          HTTP_NEGOTIATE     REMOTE_USER
#   CONTENT_TYPE            HTTP_PRAGMA        REQUEST_METHOD
#   GATEWAY_INTERFACE       HTTP_REFERER       SCRIPT_NAME
#   HTTP_ACCEPT             HTTP_USER_AGENT    SERVER_NAME
#   HTTP_ACCEPT_CHARSET     PATH_INFO          SERVER_PORT
#   HTTP_ACCEPT_ENCODING    PATH_TRANSLATED    SERVER_PROTOCOL
#   HTTP_ACCEPT_LANGUAGE    QUERY_STRING       SERVER_SOFTWARE
#   HTTP_CACHE_CONTROL      REMOTE_ADDR
#   HTTP_FROM               REMOTE_HOST
#
#
# For each of these variables, there is a corresponding attribute with the
# same name, except all lower case and without a preceding HTTP_.  
# +content_length+ and +server_port+ are integers; the rest are strings.
#
# === Parameters
#
# The method #params() returns a hash of all parameters in the request as
# name/value-list pairs, where the value-list is an Array of one or more
# values.  The CGI object itself also behaves as a hash of parameter names 
# to values, but only returns a single value (as a String) for each 
# parameter name.
#
# For instance, suppose the request contains the parameter 
# "favourite_colours" with the multiple values "blue" and "green".  The
# following behaviour would occur:
#
#   cgi.params["favourite_colours"]  # => ["blue", "green"]
#   cgi["favourite_colours"]         # => "blue"
#
# If a parameter does not exist, the former method will return an empty
# array, the latter an empty string.  The simplest way to test for existence
# of a parameter is by the #has_key? method.
#
# === Cookies
#
# HTTP Cookies are automatically parsed from the request.  They are available
# from the #cookies() accessor, which returns a hash from cookie name to
# CGI::Cookie object.
#
# === Multipart requests
#
# If a request's method is POST and its content type is multipart/form-data, 
# then it may contain uploaded files.  These are stored by the QueryExtension
# module in the parameters of the request.  The parameter name is the name
# attribute of the file input field, as usual.  However, the value is not
# a string, but an IO object, either an IOString for small files, or a
# Tempfile for larger ones.  This object also has the additional singleton
# methods:
#
# #local_path():: the path of the uploaded file on the local filesystem
# #original_filename():: the name of the file on the client computer
# #content_type():: the content type of the file
#
# == Responses
#
# The CGI class provides methods for sending header and content output to
# the HTTP client, and mixes in methods for programmatic HTML generation
# from CGI::HtmlExtension and CGI::TagMaker modules.  The precise version of HTML
# to use for HTML generation is specified at object creation time.
#
# === Writing output
#
# The simplest way to send output to the HTTP client is using the #out() method.
# This takes the HTTP headers as a hash parameter, and the body content
# via a block.  The headers can be generated as a string using the #header()
# method.  The output stream can be written directly to using the #print()
# method.
#
# === Generating HTML
#
# Each HTML element has a corresponding method for generating that
# element as a String.  The name of this method is the same as that
# of the element, all lowercase.  The attributes of the element are 
# passed in as a hash, and the body as a no-argument block that evaluates
# to a String.  The HTML generation module knows which elements are
# always empty, and silently drops any passed-in body.  It also knows
# which elements require matching closing tags and which don't.  However,
# it does not know what attributes are legal for which elements.
#
# There are also some additional HTML generation methods mixed in from
# the CGI::HtmlExtension module.  These include individual methods for the
# different types of form inputs, and methods for elements that commonly
# take particular attributes where the attributes can be directly specified
# as arguments, rather than via a hash.
#
# == Examples of use
# 
# === Get form values
# 
#   require "cgi"
#   cgi = CGI.new
#   value = cgi['field_name']   # <== value string for 'field_name'
#     # if not 'field_name' included, then return "".
#   fields = cgi.keys            # <== array of field names
# 
#   # returns true if form has 'field_name'
#   cgi.has_key?('field_name')
#   cgi.has_key?('field_name')
#   cgi.include?('field_name')
# 
# CAUTION! cgi['field_name'] returned an Array with the old 
# cgi.rb(included in ruby 1.6)
# 
# === Get form values as hash
# 
#   require "cgi"
#   cgi = CGI.new
#   params = cgi.params
# 
# cgi.params is a hash.
# 
#   cgi.params['new_field_name'] = ["value"]  # add new param
#   cgi.params['field_name'] = ["new_value"]  # change value
#   cgi.params.delete('field_name')           # delete param
#   cgi.params.clear                          # delete all params
# 
# 
# === Save form values to file
# 
#   require "pstore"
#   db = PStore.new("query.db")
#   db.transaction do
#     db["params"] = cgi.params
#   end
# 
# 
# === Restore form values from file
# 
#   require "pstore"
#   db = PStore.new("query.db")
#   db.transaction do
#     cgi.params = db["params"]
#   end
# 
# 
# === Get multipart form values
# 
#   require "cgi"
#   cgi = CGI.new
#   value = cgi['field_name']   # <== value string for 'field_name'
#   value.read                  # <== body of value
#   value.local_path            # <== path to local file of value
#   value.original_filename     # <== original filename of value
#   value.content_type          # <== content_type of value
# 
# and value has StringIO or Tempfile class methods.
# 
# === Get cookie values
# 
#   require "cgi"
#   cgi = CGI.new
#   values = cgi.cookies['name']  # <== array of 'name'
#     # if not 'name' included, then return [].
#   names = cgi.cookies.keys      # <== array of cookie names
# 
# and cgi.cookies is a hash.
# 
# === Get cookie objects
# 
#   require "cgi"
#   cgi = CGI.new
#   for name, cookie in cgi.cookies
#     cookie.expires = Time.now + 30
#   end
#   cgi.out("cookie" => cgi.cookies) {"string"}
# 
#   cgi.cookies # { "name1" => cookie1, "name2" => cookie2, ... }
# 
#   require "cgi"
#   cgi = CGI.new
#   cgi.cookies['name'].expires = Time.now + 30
#   cgi.out("cookie" => cgi.cookies['name']) {"string"}
# 
# === Print http header and html string to $DEFAULT_OUTPUT ($>)
# 
#   require "cgi"
#   cgi = CGI.new("html3")  # add HTML generation methods
#   cgi.out() do
#     cgi.html() do
#       cgi.head{ cgi.title{"TITLE"} } +
#       cgi.body() do
#         cgi.form() do
#           cgi.textarea("get_text") +
#           cgi.br +
#           cgi.submit
#         end +
#         cgi.pre() do
#           CGI::escapeHTML(
#             "params: " + cgi.params.inspect + "\n" +
#             "cookies: " + cgi.cookies.inspect + "\n" +
#             ENV.collect() do |key, value|
#               key + " --> " + value + "\n"
#             end.join("")
#           )
#         end
#       end
#     end
#   end
# 
#   # add HTML generation methods
#   CGI.new("html3")    # html3.2
#   CGI.new("html4")    # html4.01 (Strict)
#   CGI.new("html4Tr")  # html4.01 Transitional
#   CGI.new("html4Fr")  # html4.01 Frameset
#
class CGI

  # :stopdoc:

  # String for carriage return
  CR  = "\015"

  # String for linefeed
  LF  = "\012"

  # Standard internet newline sequence
  EOL = CR + LF

  REVISION = '$Id$' #:nodoc:

  NEEDS_BINMODE = true if /WIN/ni.match(RUBY_PLATFORM) 

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
    $DEFAULT_OUTPUT
  end

  private :env_table, :stdinput, :stdoutput

  # URL-encode a string.
  #   url_encoded_string = CGI::escape("'Stop!' said Fred")
  #      # => "%27Stop%21%27+said+Fred"
  def CGI::escape(string)
    string.gsub(/([^ a-zA-Z0-9_.-]+)/n) do
      '%' + $1.unpack('H2' * $1.size).join('%').upcase
    end.tr(' ', '+')
  end


  # URL-decode a string.
  #   string = CGI::unescape("%27Stop%21%27+said+Fred")
  #      # => "'Stop!' said Fred"
  def CGI::unescape(string)
    string.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n) do
      [$1.delete('%')].pack('H*')
    end
  end


  # Escape special characters in HTML, namely &\"<>
  #   CGI::escapeHTML('Usage: foo "bar" <baz>')
  #      # => "Usage: foo &quot;bar&quot; &lt;baz&gt;"
  def CGI::escapeHTML(string)
    string.gsub(/&/n, '&amp;').gsub(/\"/n, '&quot;').gsub(/>/n, '&gt;').gsub(/</n, '&lt;')
  end


  # Unescape a string that has been HTML-escaped
  #   CGI::unescapeHTML("Usage: foo &quot;bar&quot; &lt;baz&gt;")
  #      # => "Usage: foo \"bar\" <baz>"
  def CGI::unescapeHTML(string)
    string.gsub(/&(.*?);/n) do
      match = $1.dup
      case match
      when /\Aamp\z/ni           then '&'
      when /\Aquot\z/ni          then '"'
      when /\Agt\z/ni            then '>'
      when /\Alt\z/ni            then '<'
      when /\A#0*(\d+)\z/n       then
        if Integer($1) < 256
          Integer($1).chr
        else
          if Integer($1) < 65536 and ($KCODE[0] == ?u or $KCODE[0] == ?U)
            [Integer($1)].pack("U")
          else
            "&##{$1};"
          end
        end
      when /\A#x([0-9a-f]+)\z/ni then
        if $1.hex < 256
          $1.hex.chr
        else
          if $1.hex < 65536 and ($KCODE[0] == ?u or $KCODE[0] == ?U)
            [$1.hex].pack("U")
          else
            "&#x#{$1};"
          end
        end
      else
        "&#{match};"
      end
    end
  end


  # Escape only the tags of certain HTML elements in +string+.
  #
  # Takes an element or elements or array of elements.  Each element
  # is specified by the name of the element, without angle brackets.
  # This matches both the start and the end tag of that element.
  # The attribute list of the open tag will also be escaped (for
  # instance, the double-quotes surrounding attribute values).
  #
  #   print CGI::escapeElement('<BR><A HREF="url"></A>', "A", "IMG")
  #     # "<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt"
  #
  #   print CGI::escapeElement('<BR><A HREF="url"></A>', ["A", "IMG"])
  #     # "<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt"
  def CGI::escapeElement(string, *elements)
    elements = elements[0] if elements[0].kind_of?(Array)
    unless elements.empty?
      string.gsub(/<\/?(?:#{elements.join("|")})(?!\w)(?:.|\n)*?>/ni) do
        CGI::escapeHTML($&)
      end
    else
      string
    end
  end


  # Undo escaping such as that done by CGI::escapeElement()
  #
  #   print CGI::unescapeElement(
  #           CGI::escapeHTML('<BR><A HREF="url"></A>'), "A", "IMG")
  #     # "&lt;BR&gt;<A HREF="url"></A>"
  # 
  #   print CGI::unescapeElement(
  #           CGI::escapeHTML('<BR><A HREF="url"></A>'), ["A", "IMG"])
  #     # "&lt;BR&gt;<A HREF="url"></A>"
  def CGI::unescapeElement(string, *elements)
    elements = elements[0] if elements[0].kind_of?(Array)
    unless elements.empty?
      string.gsub(/&lt;\/?(?:#{elements.join("|")})(?!\w)(?:.|\n)*?&gt;/ni) do
        CGI::unescapeHTML($&)
      end
    else
      string
    end
  end


  # Format a +Time+ object as a String using the format specified by RFC 1123.
  #
  #   CGI::rfc1123_date(Time.now)
  #     # Sat, 01 Jan 2000 00:00:00 GMT
  def CGI::rfc1123_date(time)
    t = time.clone.gmtime
    return format("%s, %.2d %s %.4d %.2d:%.2d:%.2d GMT",
                RFC822_DAYS[t.wday], t.day, RFC822_MONTHS[t.month-1], t.year,
                t.hour, t.min, t.sec)
  end


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
  #
  def header(options = "text/html")

    buf = ""

    case options
    when String
      options = { "type" => options }
    when Hash
      options = options.dup
    end

    unless options.has_key?("type")
      options["type"] = "text/html"
    end

    if options.has_key?("charset")
      options["type"] += "; charset=" + options.delete("charset")
    end

    options.delete("nph") if defined?(MOD_RUBY)
    if options.delete("nph") or /IIS/n.match(env_table['SERVER_SOFTWARE'])
      buf += (env_table["SERVER_PROTOCOL"] or "HTTP/1.0")  + " " +
             (HTTP_STATUS[options["status"]] or options["status"] or "200 OK") +
             EOL +
             "Date: " + CGI::rfc1123_date(Time.now) + EOL

      unless options.has_key?("server")
        options["server"] = (env_table['SERVER_SOFTWARE'] or "")
      end

      unless options.has_key?("connection")
        options["connection"] = "close"
      end

      options.delete("status")
    end

    if options.has_key?("status")
      buf += "Status: " +
             (HTTP_STATUS[options["status"]] or options["status"]) + EOL
      options.delete("status")
    end

    if options.has_key?("server")
      buf += "Server: " + options.delete("server") + EOL
    end

    if options.has_key?("connection")
      buf += "Connection: " + options.delete("connection") + EOL
    end

    buf += "Content-Type: " + options.delete("type") + EOL

    if options.has_key?("length")
      buf += "Content-Length: " + options.delete("length").to_s + EOL
    end

    if options.has_key?("language")
      buf += "Content-Language: " + options.delete("language") + EOL
    end

    if options.has_key?("expires")
      buf += "Expires: " + CGI::rfc1123_date( options.delete("expires") ) + EOL
    end

    if options.has_key?("cookie")
      if options["cookie"].kind_of?(String) or
           options["cookie"].kind_of?(Cookie)
        buf += "Set-Cookie: " + options.delete("cookie").to_s + EOL
      elsif options["cookie"].kind_of?(Array)
        options.delete("cookie").each{|cookie|
          buf += "Set-Cookie: " + cookie.to_s + EOL
        }
      elsif options["cookie"].kind_of?(Hash)
        options.delete("cookie").each_value{|cookie|
          buf += "Set-Cookie: " + cookie.to_s + EOL
        }
      end
    end
    if @output_cookies
      for cookie in @output_cookies
        buf += "Set-Cookie: " + cookie.to_s + EOL
      end
    end

    options.each{|key, value|
      buf += key + ": " + value.to_s + EOL
    }

    if defined?(MOD_RUBY)
      table = Apache::request.headers_out
      buf.scan(/([^:]+): (.+)#{EOL}/n){ |name, value|
        warn sprintf("name:%s value:%s\n", name, value) if $DEBUG
        case name
        when 'Set-Cookie'
          table.add(name, value)
        when /^status$/ni
          Apache::request.status_line = value
          Apache::request.status = value.to_i
        when /^content-type$/ni
          Apache::request.content_type = value
        when /^content-encoding$/ni
          Apache::request.content_encoding = value
        when /^location$/ni
	  if Apache::request.status == 200
	    Apache::request.status = 302
	  end
          Apache::request.headers_out[name] = value
        else
          Apache::request.headers_out[name] = value
        end
      }
      Apache::request.send_http_header
      ''
    else
      buf + EOL
    end

  end # header()


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


  # Print an argument or list of arguments to the default output stream
  #
  #   cgi = CGI.new
  #   cgi.print    # default:  cgi.print == $DEFAULT_OUTPUT.print
  def print(*options)
    stdoutput.print(*options)
  end

  require "delegate"

  # Class representing an HTTP cookie.
  #
  # In addition to its specific fields and methods, a Cookie instance
  # is a delegator to the array of its values.
  #
  # See RFC 2965.
  #
  # == Examples of use
  #   cookie1 = CGI::Cookie::new("name", "value1", "value2", ...)
  #   cookie1 = CGI::Cookie::new("name" => "name", "value" => "value")
  #   cookie1 = CGI::Cookie::new('name'    => 'name',
  #                              'value'   => ['value1', 'value2', ...],
  #                              'path'    => 'path',   # optional
  #                              'domain'  => 'domain', # optional
  #                              'expires' => Time.now, # optional
  #                              'secure'  => true      # optional
  #                             )
  # 
  #   cgi.out("cookie" => [cookie1, cookie2]) { "string" }
  # 
  #   name    = cookie1.name
  #   values  = cookie1.value
  #   path    = cookie1.path
  #   domain  = cookie1.domain
  #   expires = cookie1.expires
  #   secure  = cookie1.secure
  # 
  #   cookie1.name    = 'name'
  #   cookie1.value   = ['value1', 'value2', ...]
  #   cookie1.path    = 'path'
  #   cookie1.domain  = 'domain'
  #   cookie1.expires = Time.now + 30
  #   cookie1.secure  = true
  class Cookie < DelegateClass(Array)

    # Create a new CGI::Cookie object.
    #
    # The contents of the cookie can be specified as a +name+ and one
    # or more +value+ arguments.  Alternatively, the contents can
    # be specified as a single hash argument.  The possible keywords of
    # this hash are as follows:
    #
    # name:: the name of the cookie.  Required.
    # value:: the cookie's value or list of values.
    # path:: the path for which this cookie applies.  Defaults to the
    #        base directory of the CGI script.
    # domain:: the domain for which this cookie applies.
    # expires:: the time at which this cookie expires, as a +Time+ object.
    # secure:: whether this cookie is a secure cookie or not (default to
    #          false).  Secure cookies are only transmitted to HTTPS 
    #          servers.
    #
    # These keywords correspond to attributes of the cookie object.
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
      else
        %r|^(.*/)|.match(ENV["SCRIPT_NAME"])
        @path = ($1 or "")
      end
      @domain = options["domain"]
      @expires = options["expires"]
      @secure = options["secure"] == true ? true : false

      super(@value)
    end

    attr_accessor("name", "value", "path", "domain", "expires")
    attr_reader("secure")

    # Set whether the Cookie is a secure cookie or not.
    #
    # +val+ must be a boolean.
    def secure=(val)
      @secure = val if val == true or val == false
      @secure
    end

    # Convert the Cookie to its string representation.
    def to_s
      buf = ""
      buf += @name + '='

      if @value.kind_of?(String)
        buf += CGI::escape(@value)
      else
        buf += @value.collect{|v| CGI::escape(v) }.join("&")
      end

      if @domain
        buf += '; domain=' + @domain
      end

      if @path
        buf += '; path=' + @path
      end

      if @expires
        buf += '; expires=' + CGI::rfc1123_date(@expires)
      end

      if @secure == true
        buf += '; secure'
      end

      buf
    end

  end # class Cookie


  # Parse a raw cookie string into a hash of cookie-name=>Cookie
  # pairs.
  #
  #   cookies = CGI::Cookie::parse("raw_cookie_string")
  #     # { "name1" => cookie1, "name2" => cookie2, ... }
  #
  def Cookie::parse(raw_cookie)
    cookies = Hash.new([])
    return cookies unless raw_cookie

    raw_cookie.split(/[;,]\s?/).each do |pairs|
      name, values = pairs.split('=',2)
      next unless name and values
      name = CGI::unescape(name)
      values ||= ""
      values = values.split('&').collect{|v| CGI::unescape(v) }
      if cookies.has_key?(name)
        values = cookies[name].value + values
      end
      cookies[name] = Cookie::new({ "name" => name, "value" => values })
    end

    cookies
  end

  # Parse an HTTP query string into a hash of key=>value pairs.
  #
  #   params = CGI::parse("query_string")
  #     # {"name1" => ["value1", "value2", ...],
  #     #  "name2" => ["value1", "value2", ...], ... }
  #
  def CGI::parse(query)
    params = Hash.new([].freeze)

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
      define_method(env.sub(/^HTTP_/n, '').downcase) do
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
      define_method(env.sub(/^HTTP_/n, '').downcase) do
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
    attr_accessor("cookies")

    # Get the parameters as a hash of name=>values pairs, where
    # values is an Array.
    attr("params")

    # Set all the parameters.
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
      stdinput.binmode if defined? stdinput.binmode
      boundary_size = boundary.size + EOL.size
      content_length -= boundary_size
      status = stdinput.read(boundary_size)
      if nil == status
        raise EOFError, "no content body"
      elsif boundary + EOL != status
        raise EOFError, "bad content body"
      end

      loop do
        head = nil
        if 10240 < content_length
          require "tempfile"
          body = Tempfile.new("CGI")
        else
          begin
            require "stringio"
            body = StringIO.new
          rescue LoadError
            require "tempfile"
            body = Tempfile.new("CGI")
          end
        end
        body.binmode if defined? body.binmode

        until head and /#{boundary}(?:#{EOL}|--)/n.match(buf)

          if (not head) and /#{EOL}#{EOL}/n.match(buf)
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
                stdinput.read(bufsize)
              else
                stdinput.read(content_length)
              end
          if c.nil?
            raise EOFError, "bad content body"
          end
          buf.concat(c)
          content_length -= c.size
        end

        buf = buf.sub(/\A((?:.|\n)*?)(?:[\r\n]{1,2})?#{boundary}([\r\n]{1,2}|--)/n) do
          body.print $1
          if "--" == $2
            content_length = -1
          end
          ""
        end

        body.rewind

        /Content-Disposition:.* filename="?([^\";]*)"?/ni.match(head)
	filename = ($1 or "")
	if /Mac/ni.match(env_table['HTTP_USER_AGENT']) and
	    /Mozilla/ni.match(env_table['HTTP_USER_AGENT']) and
	    (not /MSIE/ni.match(env_table['HTTP_USER_AGENT']))
	  filename = CGI::unescape(filename)
	end
        
        /Content-Type: (.*)/ni.match(head)
        content_type = ($1 or "")

        (class << body; self; end).class_eval do
          alias local_path path
          define_method(:original_filename) {filename.dup.taint}
          define_method(:content_type) {content_type.dup.taint}
        end

        /Content-Disposition:.* name="?([^\";]*)"?/ni.match(head)
        name = $1.dup

        if params.has_key?(name)
          params[name].push(body)
        else
          params[name] = [body]
        end
        break if buf.size == 0
        break if content_length === -1
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

      if words.find{|x| /=/n.match(x) }
        words.join('&')
      else
        words.join('+')
      end
    end
    private :read_from_cmdline

    # Initialize the data from the query.
    #
    # Handles multipart forms (in particular, forms that involve file uploads).
    # Reads query parameters in the @params field, and cookies into @cookies.
    def initialize_query()
      if ("POST" == env_table['REQUEST_METHOD']) and
         %r|\Amultipart/form-data.*boundary=\"?([^\";,]+)\"?|n.match(env_table['CONTENT_TYPE'])
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
                    end
                  )
      end

      @cookies = CGI::Cookie::parse((env_table['HTTP_COOKIE'] or env_table['COOKIE']))
    end
    private :initialize_query

    def multipart?
      @multipart
    end

    module Value    # :nodoc:
      def set_params(params)
        @params = params
      end
      def [](idx, *args)
        if args.size == 0
          warn "#{caller(1)[0]}:CAUTION! cgi['key'] == cgi.params['key'][0]; if want Array, use cgi.params['key']"
          @params[idx]
        else
          super[idx,*args]
        end
      end
      def first
        warn "#{caller(1)[0]}:CAUTION! cgi['key'] == cgi.params['key'][0]; if want Array, use cgi.params['key']"
        self
      end
      alias last first
      def to_a
        @params || [self]
      end
      alias to_ary to_a   	# to be rhs of multiple assignment
    end

    # Get the value for the parameter with a given key.
    #
    # If the parameter has multiple values, only the first will be 
    # retrieved; use #params() to get the array of values.
    def [](key)
      params = @params[key]
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
        str.extend(Value)
        str.set_params(params)
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


  # Prettify (indent) an HTML string.
  #
  # +string+ is the HTML string to indent.  +shift+ is the indentation
  # unit to use; it defaults to two spaces.
  #
  #   print CGI::pretty("<HTML><BODY></BODY></HTML>")
  #     # <HTML>
  #     #   <BODY>
  #     #   </BODY>
  #     # </HTML>
  # 
  #   print CGI::pretty("<HTML><BODY></BODY></HTML>", "\t")
  #     # <HTML>
  #     #         <BODY>
  #     #         </BODY>
  #     # </HTML>
  #
  def CGI::pretty(string, shift = "  ")
    lines = string.gsub(/(?!\A)<(?:.|\n)*?>/n, "\n\\0").gsub(/<(?:.|\n)*?>(?!\n)/n, "\\0\n")
    end_pos = 0
    while end_pos = lines.index(/^<\/(\w+)/n, end_pos)
      element = $1.dup
      start_pos = lines.rindex(/^\s*<#{element}/ni, end_pos)
      lines[start_pos ... end_pos] = "__" + lines[start_pos ... end_pos].gsub(/\n(?!\z)/n, "\n" + shift) + "__"
    end
    lines.gsub(/^((?:#{Regexp::quote(shift)})*)__(?=<\/?\w)/n, '\1')
  end


  # Base module for HTML-generation mixins.
  #
  # Provides methods for code generation for tags following
  # the various DTD element types.
  module TagMaker # :nodoc:

    # Generate code for an element with required start and end tags.
    #
    #   - -
    def nn_element_def(element)
      nOE_element_def(element, <<-END)
          if block_given?
            yield.to_s
          else
            ""
          end +
          "</#{element.upcase}>"
      END
    end

    # Generate code for an empty element.
    #
    #   - O EMPTY
    def nOE_element_def(element, append = nil)
      s = <<-END
          "<#{element.upcase}" + attributes.collect{|name, value|
            next unless value
            " " + CGI::escapeHTML(name) +
            if true == value
              ""
            else
              '="' + CGI::escapeHTML(value) + '"'
            end
          }.to_s + ">"
      END
      s.sub!(/\Z/, " +") << append if append
      s
    end

    # Generate code for an element for which the end (and possibly the
    # start) tag is optional.
    #
    #   O O or - O
    def nO_element_def(element)
      nOE_element_def(element, <<-END)
          if block_given?
            yield.to_s + "</#{element.upcase}>"
          else
            ""
          end
      END
    end

  end # TagMaker


  #
  # Mixin module providing HTML generation methods.
  #
  # For example,
  #   cgi.a("http://www.example.com") { "Example" }
  #     # => "<A HREF=\"http://www.example.com\">Example</A>"
  #
  # Modules Http3, Http4, etc., contain more basic HTML-generation methods
  # (:title, :center, etc.).
  #
  # See class CGI for a detailed example. 
  #
  module HtmlExtension


    # Generate an Anchor element as a string.
    #
    # +href+ can either be a string, giving the URL
    # for the HREF attribute, or it can be a hash of
    # the element's attributes.
    #
    # The body of the element is the string returned by the no-argument
    # block passed in.
    #
    #   a("http://www.example.com") { "Example" }
    #     # => "<A HREF=\"http://www.example.com\">Example</A>"
    #
    #   a("HREF" => "http://www.example.com", "TARGET" => "_top") { "Example" }
    #     # => "<A HREF=\"http://www.example.com\" TARGET=\"_top\">Example</A>"
    #
    def a(href = "") # :yield:
      attributes = if href.kind_of?(String)
                     { "HREF" => href }
                   else
                     href
                   end
      if block_given?
        super(attributes){ yield }
      else
        super(attributes)
      end
    end

    # Generate a Document Base URI element as a String. 
    #
    # +href+ can either by a string, giving the base URL for the HREF
    # attribute, or it can be a has of the element's attributes.
    #
    # The passed-in no-argument block is ignored.
    #
    #   base("http://www.example.com/cgi")
    #     # => "<BASE HREF=\"http://www.example.com/cgi\">"
    def base(href = "") # :yield:
      attributes = if href.kind_of?(String)
                     { "HREF" => href }
                   else
                     href
                   end
      if block_given?
        super(attributes){ yield }
      else
        super(attributes)
      end
    end

    # Generate a BlockQuote element as a string.
    #
    # +cite+ can either be a string, give the URI for the source of
    # the quoted text, or a hash, giving all attributes of the element,
    # or it can be omitted, in which case the element has no attributes.
    #
    # The body is provided by the passed-in no-argument block
    #
    #   blockquote("http://www.example.com/quotes/foo.html") { "Foo!" }
    #     #=> "<BLOCKQUOTE CITE=\"http://www.example.com/quotes/foo.html\">Foo!</BLOCKQUOTE>
    def blockquote(cite = nil)  # :yield:
      attributes = if cite.kind_of?(String)
                     { "CITE" => cite }
                   else
                     cite or ""
                   end
      if block_given?
        super(attributes){ yield }
      else
        super(attributes)
      end
    end


    # Generate a Table Caption element as a string.
    #
    # +align+ can be a string, giving the alignment of the caption
    # (one of top, bottom, left, or right).  It can be a hash of
    # all the attributes of the element.  Or it can be omitted.
    #
    # The body of the element is provided by the passed-in no-argument block.
    #
    #   caption("left") { "Capital Cities" }
    #     # => <CAPTION ALIGN=\"left\">Capital Cities</CAPTION>
    def caption(align = nil) # :yield:
      attributes = if align.kind_of?(String)
                     { "ALIGN" => align }
                   else
                     align or ""
                   end
      if block_given?
        super(attributes){ yield }
      else
        super(attributes)
      end
    end


    # Generate a Checkbox Input element as a string.
    #
    # The attributes of the element can be specified as three arguments,
    # +name+, +value+, and +checked+.  +checked+ is a boolean value;
    # if true, the CHECKED attribute will be included in the element.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   checkbox("name")
    #     # = checkbox("NAME" => "name")
    # 
    #   checkbox("name", "value")
    #     # = checkbox("NAME" => "name", "VALUE" => "value")
    # 
    #   checkbox("name", "value", true)
    #     # = checkbox("NAME" => "name", "VALUE" => "value", "CHECKED" => true)
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

    # Generate a sequence of checkbox elements, as a String.
    #
    # The checkboxes will all have the same +name+ attribute.
    # Each checkbox is followed by a label.
    # There will be one checkbox for each value.  Each value
    # can be specified as a String, which will be used both
    # as the value of the VALUE attribute and as the label
    # for that checkbox.  A single-element array has the
    # same effect.
    #
    # Each value can also be specified as a three-element array.
    # The first element is the VALUE attribute; the second is the
    # label; and the third is a boolean specifying whether this
    # checkbox is CHECKED.
    #
    # Each value can also be specified as a two-element
    # array, by omitting either the value element (defaults
    # to the same as the label), or the boolean checked element
    # (defaults to false).
    #
    #   checkbox_group("name", "foo", "bar", "baz")
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="foo">foo
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="bar">bar
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="baz">baz
    # 
    #   checkbox_group("name", ["foo"], ["bar", true], "baz")
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="foo">foo
    #     # <INPUT TYPE="checkbox" CHECKED NAME="name" VALUE="bar">bar
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="baz">baz
    # 
    #   checkbox_group("name", ["1", "Foo"], ["2", "Bar", true], "Baz")
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="1">Foo
    #     # <INPUT TYPE="checkbox" CHECKED NAME="name" VALUE="2">Bar
    #     # <INPUT TYPE="checkbox" NAME="name" VALUE="Baz">Baz
    # 
    #   checkbox_group("NAME" => "name",
    #                    "VALUES" => ["foo", "bar", "baz"])
    # 
    #   checkbox_group("NAME" => "name",
    #                    "VALUES" => [["foo"], ["bar", true], "baz"])
    # 
    #   checkbox_group("NAME" => "name",
    #                    "VALUES" => [["1", "Foo"], ["2", "Bar", true], "Baz"])
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


    # Generate an File Upload Input element as a string.
    #
    # The attributes of the element can be specified as three arguments,
    # +name+, +size+, and +maxlength+.  +maxlength+ is the maximum length
    # of the file's _name_, not of the file's _contents_.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    # See #multipart_form() for forms that include file uploads.
    #
    #   file_field("name")
    #     # <INPUT TYPE="file" NAME="name" SIZE="20">
    # 
    #   file_field("name", 40)
    #     # <INPUT TYPE="file" NAME="name" SIZE="40">
    # 
    #   file_field("name", 40, 100)
    #     # <INPUT TYPE="file" NAME="name" SIZE="40" MAXLENGTH="100">
    # 
    #   file_field("NAME" => "name", "SIZE" => 40)
    #     # <INPUT TYPE="file" NAME="name" SIZE="40">
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


    # Generate a Form element as a string.
    #
    # +method+ should be either "get" or "post", and defaults to the latter.
    # +action+ defaults to the current CGI script name.  +enctype+
    # defaults to "application/x-www-form-urlencoded".  
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    # See also #multipart_form() for forms that include file uploads.
    #
    #   form{ "string" }
    #     # <FORM METHOD="post" ENCTYPE="application/x-www-form-urlencoded">string</FORM>
    # 
    #   form("get") { "string" }
    #     # <FORM METHOD="get" ENCTYPE="application/x-www-form-urlencoded">string</FORM>
    # 
    #   form("get", "url") { "string" }
    #     # <FORM METHOD="get" ACTION="url" ENCTYPE="application/x-www-form-urlencoded">string</FORM>
    # 
    #   form("METHOD" => "post", "ENCTYPE" => "enctype") { "string" }
    #     # <FORM METHOD="post" ENCTYPE="enctype">string</FORM>
    def form(method = "post", action = script_name, enctype = "application/x-www-form-urlencoded")
      attributes = if method.kind_of?(String)
                     { "METHOD" => method, "ACTION" => action,
                       "ENCTYPE" => enctype } 
                   else
                     unless method.has_key?("METHOD")
                       method["METHOD"] = "post"
                     end
                     unless method.has_key?("ENCTYPE")
                       method["ENCTYPE"] = enctype
                     end
                     method
                   end
      if block_given?
        body = yield
      else
        body = ""
      end
      if @output_hidden
        body += @output_hidden.collect{|k,v|
          "<INPUT TYPE=\"HIDDEN\" NAME=\"#{k}\" VALUE=\"#{v}\">"
        }.to_s
      end
      super(attributes){body}
    end

    # Generate a Hidden Input element as a string.
    #
    # The attributes of the element can be specified as two arguments,
    # +name+ and +value+.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   hidden("name")
    #     # <INPUT TYPE="hidden" NAME="name">
    # 
    #   hidden("name", "value")
    #     # <INPUT TYPE="hidden" NAME="name" VALUE="value">
    # 
    #   hidden("NAME" => "name", "VALUE" => "reset", "ID" => "foo")
    #     # <INPUT TYPE="hidden" NAME="name" VALUE="value" ID="foo">
    def hidden(name = "", value = nil)
      attributes = if name.kind_of?(String)
                     { "TYPE" => "hidden", "NAME" => name, "VALUE" => value }
                   else
                     name["TYPE"] = "hidden"
                     name
                   end
      input(attributes)
    end

    # Generate a top-level HTML element as a string.
    #
    # The attributes of the element are specified as a hash.  The
    # pseudo-attribute "PRETTY" can be used to specify that the generated
    # HTML string should be indented.  "PRETTY" can also be specified as
    # a string as the sole argument to this method.  The pseudo-attribute
    # "DOCTYPE", if given, is used as the leading DOCTYPE SGML tag; it
    # should include the entire text of this tag, including angle brackets.
    #
    # The body of the html element is supplied as a block.
    # 
    #   html{ "string" }
    #     # <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN"><HTML>string</HTML>
    # 
    #   html("LANG" => "ja") { "string" }
    #     # <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN"><HTML LANG="ja">string</HTML>
    # 
    #   html("DOCTYPE" => false) { "string" }
    #     # <HTML>string</HTML>
    # 
    #   html("DOCTYPE" => '<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">') { "string" }
    #     # <!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN"><HTML>string</HTML>
    # 
    #   html("PRETTY" => "  ") { "<BODY></BODY>" }
    #     # <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
    #     # <HTML>
    #     #   <BODY>
    #     #   </BODY>
    #     # </HTML>
    # 
    #   html("PRETTY" => "\t") { "<BODY></BODY>" }
    #     # <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
    #     # <HTML>
    #     #         <BODY>
    #     #         </BODY>
    #     # </HTML>
    # 
    #   html("PRETTY") { "<BODY></BODY>" }
    #     # = html("PRETTY" => "  ") { "<BODY></BODY>" }
    # 
    #   html(if $VERBOSE then "PRETTY" end) { "HTML string" }
    #
    def html(attributes = {}) # :yield:
      if nil == attributes
        attributes = {}
      elsif "PRETTY" == attributes
        attributes = { "PRETTY" => true }
      end
      pretty = attributes.delete("PRETTY")
      pretty = "  " if true == pretty
      buf = ""

      if attributes.has_key?("DOCTYPE")
        if attributes["DOCTYPE"]
          buf += attributes.delete("DOCTYPE")
        else
          attributes.delete("DOCTYPE")
        end
      else
        buf += doctype
      end

      if block_given?
        buf += super(attributes){ yield }
      else
        buf += super(attributes)
      end

      if pretty
        CGI::pretty(buf, pretty)
      else
        buf
      end

    end

    # Generate an Image Button Input element as a string.
    #
    # +src+ is the URL of the image to use for the button.  +name+ 
    # is the input name.  +alt+ is the alternative text for the image.
    #
    # Alternatively, the attributes can be specified as a hash.
    # 
    #   image_button("url")
    #     # <INPUT TYPE="image" SRC="url">
    # 
    #   image_button("url", "name", "string")
    #     # <INPUT TYPE="image" SRC="url" NAME="name" ALT="string">
    # 
    #   image_button("SRC" => "url", "ATL" => "strng")
    #     # <INPUT TYPE="image" SRC="url" ALT="string">
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


    # Generate an Image element as a string.
    #
    # +src+ is the URL of the image.  +alt+ is the alternative text for
    # the image.  +width+ is the width of the image, and +height+ is
    # its height.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   img("src", "alt", 100, 50)
    #     # <IMG SRC="src" ALT="alt" WIDTH="100" HEIGHT="50">
    # 
    #   img("SRC" => "src", "ALT" => "alt", "WIDTH" => 100, "HEIGHT" => 50)
    #     # <IMG SRC="src" ALT="alt" WIDTH="100" HEIGHT="50">
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


    # Generate a Form element with multipart encoding as a String.
    #
    # Multipart encoding is used for forms that include file uploads.
    #
    # +action+ is the action to perform.  +enctype+ is the encoding
    # type, which defaults to "multipart/form-data".
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   multipart_form{ "string" }
    #     # <FORM METHOD="post" ENCTYPE="multipart/form-data">string</FORM>
    # 
    #   multipart_form("url") { "string" }
    #     # <FORM METHOD="post" ACTION="url" ENCTYPE="multipart/form-data">string</FORM>
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
      if block_given?
        form(attributes){ yield }
      else
        form(attributes)
      end
    end


    # Generate a Password Input element as a string.
    #
    # +name+ is the name of the input field.  +value+ is its default
    # value.  +size+ is the size of the input field display.  +maxlength+
    # is the maximum length of the inputted password.
    #
    # Alternatively, attributes can be specified as a hash.
    #
    #   password_field("name")
    #     # <INPUT TYPE="password" NAME="name" SIZE="40">
    # 
    #   password_field("name", "value")
    #     # <INPUT TYPE="password" NAME="name" VALUE="value" SIZE="40">
    # 
    #   password_field("password", "value", 80, 200)
    #     # <INPUT TYPE="password" NAME="name" VALUE="value" SIZE="80" MAXLENGTH="200">
    # 
    #   password_field("NAME" => "name", "VALUE" => "value")
    #     # <INPUT TYPE="password" NAME="name" VALUE="value">
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

    # Generate a Select element as a string.
    #
    # +name+ is the name of the element.  The +values+ are the options that
    # can be selected from the Select menu.  Each value can be a String or
    # a one, two, or three-element Array.  If a String or a one-element
    # Array, this is both the value of that option and the text displayed for
    # it.  If a three-element Array, the elements are the option value, displayed
    # text, and a boolean value specifying whether this option starts as selected.
    # The two-element version omits either the option value (defaults to the same
    # as the display text) or the boolean selected specifier (defaults to false).
    #
    # The attributes and options can also be specified as a hash.  In this
    # case, options are specified as an array of values as described above,
    # with the hash key of "VALUES".
    #
    #   popup_menu("name", "foo", "bar", "baz")
    #     # <SELECT NAME="name">
    #     #   <OPTION VALUE="foo">foo</OPTION>
    #     #   <OPTION VALUE="bar">bar</OPTION>
    #     #   <OPTION VALUE="baz">baz</OPTION>
    #     # </SELECT>
    # 
    #   popup_menu("name", ["foo"], ["bar", true], "baz")
    #     # <SELECT NAME="name">
    #     #   <OPTION VALUE="foo">foo</OPTION>
    #     #   <OPTION VALUE="bar" SELECTED>bar</OPTION>
    #     #   <OPTION VALUE="baz">baz</OPTION>
    #     # </SELECT>
    # 
    #   popup_menu("name", ["1", "Foo"], ["2", "Bar", true], "Baz")
    #     # <SELECT NAME="name">
    #     #   <OPTION VALUE="1">Foo</OPTION>
    #     #   <OPTION SELECTED VALUE="2">Bar</OPTION>
    #     #   <OPTION VALUE="Baz">Baz</OPTION>
    #     # </SELECT>
    # 
    #   popup_menu("NAME" => "name", "SIZE" => 2, "MULTIPLE" => true,
    #               "VALUES" => [["1", "Foo"], ["2", "Bar", true], "Baz"])
    #     # <SELECT NAME="name" MULTIPLE SIZE="2">
    #     #   <OPTION VALUE="1">Foo</OPTION>
    #     #   <OPTION SELECTED VALUE="2">Bar</OPTION>
    #     #   <OPTION VALUE="Baz">Baz</OPTION>
    #     # </SELECT>
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

    # Generates a radio-button Input element.
    #
    # +name+ is the name of the input field.  +value+ is the value of
    # the field if checked.  +checked+ specifies whether the field
    # starts off checked.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   radio_button("name", "value")
    #     # <INPUT TYPE="radio" NAME="name" VALUE="value">
    # 
    #   radio_button("name", "value", true)
    #     # <INPUT TYPE="radio" NAME="name" VALUE="value" CHECKED>
    # 
    #   radio_button("NAME" => "name", "VALUE" => "value", "ID" => "foo")
    #     # <INPUT TYPE="radio" NAME="name" VALUE="value" ID="foo">
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

    # Generate a sequence of radio button Input elements, as a String.
    #
    # This works the same as #checkbox_group().  However, it is not valid
    # to have more than one radiobutton in a group checked.
    # 
    #   radio_group("name", "foo", "bar", "baz")
    #     # <INPUT TYPE="radio" NAME="name" VALUE="foo">foo
    #     # <INPUT TYPE="radio" NAME="name" VALUE="bar">bar
    #     # <INPUT TYPE="radio" NAME="name" VALUE="baz">baz
    # 
    #   radio_group("name", ["foo"], ["bar", true], "baz")
    #     # <INPUT TYPE="radio" NAME="name" VALUE="foo">foo
    #     # <INPUT TYPE="radio" CHECKED NAME="name" VALUE="bar">bar
    #     # <INPUT TYPE="radio" NAME="name" VALUE="baz">baz
    # 
    #   radio_group("name", ["1", "Foo"], ["2", "Bar", true], "Baz")
    #     # <INPUT TYPE="radio" NAME="name" VALUE="1">Foo
    #     # <INPUT TYPE="radio" CHECKED NAME="name" VALUE="2">Bar
    #     # <INPUT TYPE="radio" NAME="name" VALUE="Baz">Baz
    # 
    #   radio_group("NAME" => "name",
    #                 "VALUES" => ["foo", "bar", "baz"])
    # 
    #   radio_group("NAME" => "name",
    #                 "VALUES" => [["foo"], ["bar", true], "baz"])
    # 
    #   radio_group("NAME" => "name",
    #                 "VALUES" => [["1", "Foo"], ["2", "Bar", true], "Baz"])
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

    # Generate a reset button Input element, as a String.
    #
    # This resets the values on a form to their initial values.  +value+
    # is the text displayed on the button. +name+ is the name of this button.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   reset
    #     # <INPUT TYPE="reset">
    # 
    #   reset("reset")
    #     # <INPUT TYPE="reset" VALUE="reset">
    # 
    #   reset("VALUE" => "reset", "ID" => "foo")
    #     # <INPUT TYPE="reset" VALUE="reset" ID="foo">
    def reset(value = nil, name = nil)
      attributes = if (not value) or value.kind_of?(String)
                     { "TYPE" => "reset", "VALUE" => value, "NAME" => name }
                   else
                     value["TYPE"] = "reset"
                     value
                   end
      input(attributes)
    end

    alias scrolling_list popup_menu

    # Generate a submit button Input element, as a String.
    #
    # +value+ is the text to display on the button.  +name+ is the name
    # of the input.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   submit
    #     # <INPUT TYPE="submit">
    # 
    #   submit("ok")
    #     # <INPUT TYPE="submit" VALUE="ok">
    # 
    #   submit("ok", "button1")
    #     # <INPUT TYPE="submit" VALUE="ok" NAME="button1">
    # 
    #   submit("VALUE" => "ok", "NAME" => "button1", "ID" => "foo")
    #     # <INPUT TYPE="submit" VALUE="ok" NAME="button1" ID="foo">
    def submit(value = nil, name = nil)
      attributes = if (not value) or value.kind_of?(String)
                     { "TYPE" => "submit", "VALUE" => value, "NAME" => name }
                   else
                     value["TYPE"] = "submit"
                     value
                   end
      input(attributes)
    end

    # Generate a text field Input element, as a String.
    #
    # +name+ is the name of the input field.  +value+ is its initial
    # value.  +size+ is the size of the input area.  +maxlength+
    # is the maximum length of input accepted.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    #   text_field("name")
    #     # <INPUT TYPE="text" NAME="name" SIZE="40">
    # 
    #   text_field("name", "value")
    #     # <INPUT TYPE="text" NAME="name" VALUE="value" SIZE="40">
    # 
    #   text_field("name", "value", 80)
    #     # <INPUT TYPE="text" NAME="name" VALUE="value" SIZE="80">
    # 
    #   text_field("name", "value", 80, 200)
    #     # <INPUT TYPE="text" NAME="name" VALUE="value" SIZE="80" MAXLENGTH="200">
    # 
    #   text_field("NAME" => "name", "VALUE" => "value")
    #     # <INPUT TYPE="text" NAME="name" VALUE="value">
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

    # Generate a TextArea element, as a String.
    #
    # +name+ is the name of the textarea.  +cols+ is the number of
    # columns and +rows+ is the number of rows in the display.
    #
    # Alternatively, the attributes can be specified as a hash.
    #
    # The body is provided by the passed-in no-argument block
    #
    #   textarea("name")
    #      # = textarea("NAME" => "name", "COLS" => 70, "ROWS" => 10)
    #
    #   textarea("name", 40, 5)
    #      # = textarea("NAME" => "name", "COLS" => 40, "ROWS" => 5)
    def textarea(name = "", cols = 70, rows = 10)  # :yield:
      attributes = if name.kind_of?(String)
                     { "NAME" => name, "COLS" => cols.to_s,
                       "ROWS" => rows.to_s }
                   else
                     name
                   end
      if block_given?
        super(attributes){ yield }
      else
        super(attributes)
      end
    end

  end # HtmlExtension


  # Mixin module for HTML version 3 generation methods.
  module Html3 # :nodoc:

    # The DOCTYPE declaration for this version of HTML
    def doctype
      %|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">|
    end

    # Initialise the HTML generation methods for this version.
    def element_init
      extend TagMaker
      methods = ""
      # - -
      for element in %w[ A TT I B U STRIKE BIG SMALL SUB SUP EM STRONG
          DFN CODE SAMP KBD VAR CITE FONT ADDRESS DIV center MAP
          APPLET PRE XMP LISTING DL OL UL DIR MENU SELECT table TITLE
          STYLE SCRIPT H1 H2 H3 H4 H5 H6 TEXTAREA FORM BLOCKQUOTE
          CAPTION ]
        methods += <<-BEGIN + nn_element_def(element) + <<-END
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # - O EMPTY
      for element in %w[ IMG BASE BASEFONT BR AREA LINK PARAM HR INPUT
          ISINDEX META ]
        methods += <<-BEGIN + nOE_element_def(element) + <<-END
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # O O or - O
      for element in %w[ HTML HEAD BODY P PLAINTEXT DT DD LI OPTION tr
          th td ]
        methods += <<-BEGIN + nO_element_def(element) + <<-END
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end
      eval(methods)
    end

  end # Html3


  # Mixin module for HTML version 4 generation methods.
  module Html4 # :nodoc:

    # The DOCTYPE declaration for this version of HTML
    def doctype
      %|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">|
    end

    # Initialise the HTML generation methods for this version.
    def element_init
      extend TagMaker
      methods = ""
      # - -
      for element in %w[ TT I B BIG SMALL EM STRONG DFN CODE SAMP KBD
        VAR CITE ABBR ACRONYM SUB SUP SPAN BDO ADDRESS DIV MAP OBJECT
        H1 H2 H3 H4 H5 H6 PRE Q INS DEL DL OL UL LABEL SELECT OPTGROUP
        FIELDSET LEGEND BUTTON TABLE TITLE STYLE SCRIPT NOSCRIPT
        TEXTAREA FORM A BLOCKQUOTE CAPTION ]
        methods += <<-BEGIN + nn_element_def(element) + <<-END
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # - O EMPTY
      for element in %w[ IMG BASE BR AREA LINK PARAM HR INPUT COL META ]
        methods += <<-BEGIN + nOE_element_def(element) + <<-END
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # O O or - O
      for element in %w[ HTML BODY P DT DD LI OPTION THEAD TFOOT TBODY
          COLGROUP TR TH TD HEAD]
        methods += <<-BEGIN + nO_element_def(element) + <<-END
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end
      eval(methods)
    end

  end # Html4


  # Mixin module for HTML version 4 transitional generation methods.
  module Html4Tr # :nodoc:

    # The DOCTYPE declaration for this version of HTML
    def doctype
      %|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">|
    end

    # Initialise the HTML generation methods for this version.
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
        methods += <<-BEGIN + nn_element_def(element) + <<-END
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # - O EMPTY
      for element in %w[ IMG BASE BASEFONT BR AREA LINK PARAM HR INPUT
          COL ISINDEX META ]
        methods += <<-BEGIN + nOE_element_def(element) + <<-END
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # O O or - O
      for element in %w[ HTML BODY P DT DD LI OPTION THEAD TFOOT TBODY
          COLGROUP TR TH TD HEAD ]
        methods += <<-BEGIN + nO_element_def(element) + <<-END
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end
      eval(methods)
    end

  end # Html4Tr


  # Mixin module for generating HTML version 4 with framesets.
  module Html4Fr # :nodoc:

    # The DOCTYPE declaration for this version of HTML
    def doctype
      %|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Frameset//EN" "http://www.w3.org/TR/html4/frameset.dtd">|
    end

    # Initialise the HTML generation methods for this version.
    def element_init
      methods = ""
      # - -
      for element in %w[ FRAMESET ]
        methods += <<-BEGIN + nn_element_def(element) + <<-END
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end

      # - O EMPTY
      for element in %w[ FRAME ]
        methods += <<-BEGIN + nOE_element_def(element) + <<-END
          def #{element.downcase}(attributes = {})
        BEGIN
          end
        END
      end
      eval(methods)
    end

  end # Html4Fr


  # Creates a new CGI instance.
  #
  # +type+ specifies which version of HTML to load the HTML generation
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
  # CGI locations, which varies according to the REQUEST_METHOD.
  def initialize(type = "query")
    if defined?(MOD_RUBY) && !ENV.key?("GATEWAY_INTERFACE")
      Apache.request.setup_cgi_env
    end

    extend QueryExtension
    @multipart = false
    if defined?(CGI_PARAMS)
      warn "do not use CGI_PARAMS and CGI_COOKIES"
      @params = CGI_PARAMS.dup
      @cookies = CGI_COOKIES.dup
    else
      initialize_query()  # set @params, @cookies
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
      extend Html4Tr
      element_init()
      extend Html4Fr
      element_init()
      extend HtmlExtension
    end
  end

end   # class CGI
