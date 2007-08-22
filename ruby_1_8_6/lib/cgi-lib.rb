warn "Warning:#{caller[0].sub(/:in `.*'\z/, '')}: cgi-lib is deprecated after Ruby 1.8.1; use cgi instead"

=begin

= simple CGI support library

= example

== get form values

	require "cgi-lib.rb"
	query = CGI.new
	query['field']   # <== value of 'field'
	query.keys       # <== array of fields

and query has Hash class methods


== get cookie values

	require "cgi-lib.rb"
	query = CGI.new
	query.cookie['name']  # <== cookie value of 'name'
	query.cookie.keys     # <== all cookie names

and query.cookie has Hash class methods


== print HTTP header and HTML string to $>

	require "cgi-lib.rb"
	CGI::print{
	  CGI::tag("HTML"){
	    CGI::tag("HEAD"){ CGI::tag("TITLE"){"TITLE"} } +
	    CGI::tag("BODY"){
	      CGI::tag("FORM", {"ACTION"=>"test.rb", "METHOD"=>"POST"}){
	        CGI::tag("INPUT", {"TYPE"=>"submit", "VALUE"=>"submit"})
	      } +
	      CGI::tag("HR")
	    }
	  }
	}


== make raw cookie string

	require "cgi-lib.rb"
	cookie1 = CGI::cookie({'name'    => 'name',
	                       'value'   => 'value',
	                       'path'    => 'path',   # optional
	                       'domain'  => 'domain', # optional
	                       'expires' => Time.now, # optional
	                       'secure'  => true      # optional
	                      })

	CGI::print("Content-Type: text/html", cookie1, cookie2){ "string" }


== print HTTP header and string to $>

	require "cgi-lib.rb"
	CGI::print{ "string" }
	  # == CGI::print("Content-Type: text/html"){ "string" }
	CGI::print("Content-Type: text/html", cookie1, cookie2){ "string" }


=== NPH (no-parse-header) mode

	require "cgi-lib.rb"
	CGI::print("nph"){ "string" }
	  # == CGI::print("nph", "Content-Type: text/html"){ "string" }
	CGI::print("nph", "Content-Type: text/html", cookie1, cookie2){ "string" }


== make HTML tag string

	require "cgi-lib.rb"
	CGI::tag("element", {"attribute_name"=>"attribute_value"}){"content"}


== make HTTP header string

	require "cgi-lib.rb"
	CGI::header # == CGI::header("Content-Type: text/html")
	CGI::header("Content-Type: text/html", cookie1, cookie2)


=== NPH (no-parse-header) mode

	CGI::header("nph") # == CGI::header("nph", "Content-Type: text/html")
	CGI::header("nph", "Content-Type: text/html", cookie1, cookie2)


== escape url encode

	require "cgi-lib.rb"
	url_encoded_string = CGI::escape("string")


== unescape url encoded

	require "cgi-lib.rb"
	string = CGI::unescape("url encoded string")


== escape HTML &"<>

	require "cgi-lib.rb"
	CGI::escapeHTML("string")


=end

require "delegate"

class CGI < SimpleDelegator

  CR  = "\015"
  LF  = "\012"
  EOL = CR + LF

  RFC822_DAYS = %w[ Sun Mon Tue Wed Thu Fri Sat ]
  RFC822_MONTHS = %w[ Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec ]

  # make rfc1123 date string
  def CGI::rfc1123_date(time)
    t = time.clone.gmtime
    return format("%s, %.2d %s %d %.2d:%.2d:%.2d GMT",
                RFC822_DAYS[t.wday], t.day, RFC822_MONTHS[t.month-1], t.year,
                t.hour, t.min, t.sec)
  end

  # escape url encode
  def CGI::escape(str)
    str.gsub(/[^a-zA-Z0-9_\-.]/n){ sprintf("%%%02X", $&.unpack("C")[0]) }
  end

  # unescape url encoded
  def CGI::unescape(str)
    str.gsub(/\+/, ' ').gsub(/%([0-9a-fA-F]{2})/){ [$1.hex].pack("c") }
  end

  # escape HTML
  def CGI::escapeHTML(str)
    str.gsub(/&/, "&amp;").gsub(/\"/, "&quot;").gsub(/>/, "&gt;").gsub(/</, "&lt;")
  end

  # offline mode. read name=value pairs on standard input.
  def read_from_cmdline
    require "shellwords.rb"
    words = Shellwords.shellwords(
              if not ARGV.empty?
                ARGV.join(' ')
              else
                STDERR.print "(offline mode: enter name=value pairs on standard input)\n" if STDIN.tty?
                readlines.join(' ').gsub(/\n/, '')
              end.gsub(/\\=/, '%3D').gsub(/\\&/, '%26'))

    if words.find{|x| x =~ /=/} then words.join('&') else words.join('+') end
  end

  def initialize(input = $stdin)

    @inputs = {}
    @cookie = {}

    case ENV['REQUEST_METHOD']
    when "GET"
      ENV['QUERY_STRING'] or ""
    when "POST"
      input.read(Integer(ENV['CONTENT_LENGTH'])) or ""
    else
      read_from_cmdline
    end.split(/[&;]/).each do |x|
      key, val = x.split(/=/,2).collect{|x|CGI::unescape(x)}
      if @inputs.include?(key)
        @inputs[key] += "\0" + (val or "")
      else
        @inputs[key] = (val or "")
      end
    end

    super(@inputs)

    if ENV.has_key?('HTTP_COOKIE') or ENV.has_key?('COOKIE')
      (ENV['HTTP_COOKIE'] or ENV['COOKIE']).split(/; /).each do |x|
        key, val = x.split(/=/,2)
        key = CGI::unescape(key)
        val = val.split(/&/).collect{|x|CGI::unescape(x)}.join("\0")
        if @cookie.include?(key)
          @cookie[key] += "\0" + val
        else
          @cookie[key] = val
        end
      end
    end
  end

  attr("inputs")
  attr("cookie")

  # make HTML tag string
  def CGI::tag(element, attributes = {})
    "<" + escapeHTML(element) + attributes.collect{|name, value|
      " " + escapeHTML(name) + '="' + escapeHTML(value) + '"'
    }.to_s + ">" +
    (iterator? ? yield.to_s + "</" + escapeHTML(element) + ">" : "")
  end

  # make raw cookie string
  def CGI::cookie(options)
    "Set-Cookie: " + options['name'] + '=' + escape(options['value']) +
    (options['domain']  ? '; domain='  + options['domain'] : '') +
    (options['path']    ? '; path='    + options['path']   : '') +
    (options['expires'] ? '; expires=' + rfc1123_date(options['expires']) : '') +
    (options['secure']  ? '; secure' : '')
  end

  # make HTTP header string
  def CGI::header(*options)
    if defined?(MOD_RUBY)
      options.each{|option|
        option.sub(/(.*?): (.*)/){
          Apache::request.headers_out[$1] = $2
        }
      }
      Apache::request.send_http_header
      ''
    else
      if options.delete("nph") or (ENV['SERVER_SOFTWARE'] =~ /IIS/)
        [(ENV['SERVER_PROTOCOL'] or "HTTP/1.0") + " 200 OK",
         "Date: " + rfc1123_date(Time.now),
         "Server: " + (ENV['SERVER_SOFTWARE'] or ""),
         "Connection: close"] +
        (options.empty? ? ["Content-Type: text/html"] : options)
      else
        options.empty? ? ["Content-Type: text/html"] : options
      end.join(EOL) + EOL + EOL
    end
  end

  # print HTTP header and string to $>
  def CGI::print(*options)
    $>.print CGI::header(*options) + yield.to_s
  end

  # print message to $>
  def CGI::message(message, title = "", header = ["Content-Type: text/html"])
    if message.kind_of?(Hash)
      title   = message['title']
      header  = message['header']
      message = message['body']
    end
    CGI::print(*header){
      CGI::tag("HTML"){
        CGI::tag("HEAD"){ CGI.tag("TITLE"){ title } } +
        CGI::tag("BODY"){ message }
      }
    }
    true
  end

  # print error message to $> and exit
  def CGI::error
    CGI::message({'title'=>'ERROR', 'body'=>
      CGI::tag("PRE"){
        "ERROR: " + CGI::tag("STRONG"){ escapeHTML($!.to_s) } + "\n" + escapeHTML($@.join("\n"))
      }
    })
    exit
  end
end
