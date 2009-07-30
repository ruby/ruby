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
class CGI
  class Cookie < Array

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
      if name.kind_of?(String)
        @name = name
        @value = value
        %r|^(.*/)|.match(ENV["SCRIPT_NAME"])
        @path = ($1 or "")
        @secure = false
        return super(@value)
      end

      options = name
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
      val = @value.kind_of?(String) ? CGI::escape(@value) : @value.collect{|v| CGI::escape(v) }.join("&")
      buf = "#{@name}=#{val}"
      buf << "; domain=#{@domain}" if @domain
      buf << "; path=#{@path}"     if @path
      buf << "; expires=#{CGI::rfc1123_date(@expires)}" if @expires
      buf << "; secure"            if @secure == true
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
      values = values.split('&').collect{|v| CGI::unescape(v,@@accept_charset) }
      if cookies.has_key?(name)
        values = cookies[name].value + values
      end
      cookies[name] = Cookie::new(name, *values)
    end

    cookies
  end
end


