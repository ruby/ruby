# frozen_string_literal: false
#
# The \HTTPHeader module provides access to \HTTP headers.
#
# The module is included in:
#
# - Net::HTTPGenericRequest (and therefore Net::HTTPRequest).
# - Net::HTTPResponse.
#
# The headers are a hash-like collection of key/value pairs called _fields_.
#
# == Request and Response Fields
#
# Headers may be included in:
#
# - A Net::HTTPRequest object:
#   the object's headers will be sent with the request.
#   Any fields may be defined in the request;
#   see {Setters}[rdoc-ref:Net::HTTPHeader@Setters].
# - A Net::HTTPResponse object:
#   the objects headers are usually those returned from the host.
#   Fields may be retrieved from the object;
#   see {Getters}[rdoc-ref:Net::HTTPHeader@Getters]
#   and {Iterators}[rdoc-ref:Net::HTTPHeader@Iterators].
#
# Exactly which fields should be sent or expected depends on the host;
# see:
#
# - {Request fields}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#Request_fields].
# - {Response fields}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#Response_fields].
#
# == About the Examples
#
# :include: doc/net-http/examples.rdoc
#
# == Fields
#
# A header field is a key/value pair.
#
# === Field Keys
#
# A field key may be:
#
# - A string: Key <tt>'Accept'</tt> is treated as if it were
#   <tt>'Accept'.downcase</tt>;  i.e., <tt>'accept'</tt>.
# - A symbol: Key <tt>:Accept</tt> is treated as if it were
#   <tt>:Accept.to_s.downcase</tt>;  i.e., <tt>'accept'</tt>.
#
# Examples:
#
#   req = Net::HTTP::Get.new(uri)
#   req[:accept]  # => "*/*"
#   req['Accept'] # => "*/*"
#   req['ACCEPT'] # => "*/*"
#
#   req['accept'] = 'text/html'
#   req[:accept] = 'text/html'
#   req['ACCEPT'] = 'text/html'
#
# === Field Values
#
# A field value may be returned as an array of strings or as a string:
#
# - These methods return field values as arrays:
#
#   - #get_fields: Returns the array value for the given key,
#     or +nil+ if it does not exist.
#   - #to_hash: Returns a hash of all header fields:
#     each key is a field name; its value is the array value for the field.
#
# - These methods return field values as string;
#   the string value for a field is equivalent to
#   <tt>self[key.downcase.to_s].join(', '))</tt>:
#
#   - #[]: Returns the string value for the given key,
#     or +nil+ if it does not exist.
#   - #fetch: Like #[], but accepts a default value
#     to be returned if the key does not exist.
#
# The field value may be set:
#
# - #[]=: Sets the value for the given key;
#   the given value may be a string, a symbol, an array, or a hash.
# - #add_field: Adds a given value to a value for the given key
#   (not overwriting the existing value).
# - #delete: Deletes the field for the given key.
#
# Example field values:
#
# - \String:
#
#     req['Accept'] = 'text/html' # => "text/html"
#     req['Accept']               # => "text/html"
#     req.get_fields('Accept')    # => ["text/html"]
#
# - \Symbol:
#
#     req['Accept'] = :text    # => :text
#     req['Accept']            # => "text"
#     req.get_fields('Accept') # => ["text"]
#
# - Simple array:
#
#     req[:foo] = %w[bar baz bat]
#     req[:foo]            # => "bar, baz, bat"
#     req.get_fields(:foo) # => ["bar", "baz", "bat"]
#
# - Simple hash:
#
#     req[:foo] = {bar: 0, baz: 1, bat: 2}
#     req[:foo]            # => "bar, 0, baz, 1, bat, 2"
#     req.get_fields(:foo) # => ["bar", "0", "baz", "1", "bat", "2"]
#
# - Nested:
#
#     req[:foo] = [%w[bar baz], {bat: 0, bam: 1}]
#     req[:foo]            # => "bar, baz, bat, 0, bam, 1"
#     req.get_fields(:foo) # => ["bar", "baz", "bat", "0", "bam", "1"]
#
#     req[:foo] = {bar: %w[baz bat], bam: {bah: 0, bad: 1}}
#     req[:foo]            # => "bar, baz, bat, bam, bah, 0, bad, 1"
#     req.get_fields(:foo) # => ["bar", "baz", "bat", "bam", "bah", "0", "bad", "1"]
#
# == Convenience Methods
#
# Various convenience methods retrieve values, set values, query values,
# set form values, or iterate over fields.
#
# === Setters
#
# \Method #[]= can set any field, but does little to validate the new value;
# some of the other setter methods provide some validation:
#
# - #[]=: Sets the string or array value for the given key.
# - #add_field: Creates or adds to the array value for the given key.
# - #basic_auth: Sets the string authorization header for <tt>'Authorization'</tt>.
# - #content_length=: Sets the integer length for field <tt>'Content-Length</tt>.
# - #content_type=: Sets the string value for field <tt>'Content-Type'</tt>.
# - #proxy_basic_auth: Sets the string authorization header for <tt>'Proxy-Authorization'</tt>.
# - #set_range: Sets the value for field <tt>'Range'</tt>.
#
# === Form Setters
#
# - #set_form: Sets an HTML form data set.
# - #set_form_data: Sets header fields and a body from HTML form data.
#
# === Getters
#
# \Method #[] can retrieve the value of any field that exists,
# but always as a string;
# some of the other getter methods return something different
# from the simple string value:
#
# - #[]: Returns the string field value for the given key.
# - #content_length: Returns the integer value of field <tt>'Content-Length'</tt>.
# - #content_range: Returns the Range value of field <tt>'Content-Range'</tt>.
# - #content_type: Returns the string value of field <tt>'Content-Type'</tt>.
# - #fetch: Returns the string field value for the given key.
# - #get_fields: Returns the array field value for the given +key+.
# - #main_type: Returns first part of the string value of field <tt>'Content-Type'</tt>.
# - #sub_type: Returns second part of the string value of field <tt>'Content-Type'</tt>.
# - #range: Returns an array of Range objects of field <tt>'Range'</tt>, or +nil+.
# - #range_length: Returns the integer length of the range given in field <tt>'Content-Range'</tt>.
# - #type_params: Returns the string parameters for <tt>'Content-Type'</tt>.
#
# === Queries
#
# - #chunked?: Returns whether field <tt>'Transfer-Encoding'</tt> is set to <tt>'chunked'</tt>.
# - #connection_close?: Returns whether field <tt>'Connection'</tt> is set to <tt>'close'</tt>.
# - #connection_keep_alive?: Returns whether field <tt>'Connection'</tt> is set to <tt>'keep-alive'</tt>.
# - #key?: Returns whether a given key exists.
#
# === Iterators
#
# - #each_capitalized: Passes each field capitalized-name/value pair to the block.
# - #each_capitalized_name: Passes each capitalized field name to the block.
# - #each_header: Passes each field name/value pair to the block.
# - #each_name: Passes each field name to the block.
# - #each_value: Passes each string field value to the block.
#
module Net::HTTPHeader

  def initialize_http_header(initheader) #:nodoc:
    @header = {}
    return unless initheader
    initheader.each do |key, value|
      warn "net/http: duplicated HTTP header: #{key}", uplevel: 3 if key?(key) and $VERBOSE
      if value.nil?
        warn "net/http: nil HTTP header: #{key}", uplevel: 3 if $VERBOSE
      else
        value = value.strip # raise error for invalid byte sequences
        if value.count("\r\n") > 0
          raise ArgumentError, "header #{key} has field value #{value.inspect}, this cannot include CR/LF"
        end
        @header[key.downcase.to_s] = [value]
      end
    end
  end

  def size   #:nodoc: obsolete
    @header.size
  end

  alias length size   #:nodoc: obsolete

  # Returns the string field value for the case-insensitive field +key+,
  # or +nil+ if there is no such key;
  # see {Fields}[rdoc-ref:Net::HTTPHeader@Fields]:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res['Connection'] # => "keep-alive"
  #   res['Nosuch']     # => nil
  #
  # Note that some field values may be retrieved via convenience methods;
  # see {Getters}[rdoc-ref:Net::HTTPHeader@Getters].
  def [](key)
    a = @header[key.downcase.to_s] or return nil
    a.join(', ')
  end

  # Sets the value for the case-insensitive +key+ to +val+,
  # overwriting the previous value if the field exists;
  # see {Fields}[rdoc-ref:Net::HTTPHeader@Fields]:
  #
  #   req = Net::HTTP::Get.new(uri)
  #   req['Accept'] # => "*/*"
  #   req['Accept'] = 'text/html'
  #   req['Accept'] # => "text/html"
  #
  # Note that some field values may be set via convenience methods;
  # see {Setters}[rdoc-ref:Net::HTTPHeader@Setters].
  def []=(key, val)
    unless val
      @header.delete key.downcase.to_s
      return val
    end
    set_field(key, val)
  end

  # Adds value +val+ to the value array for field +key+ if the field exists;
  # creates the field with the given +key+ and +val+ if it does not exist.
  # see {Fields}[rdoc-ref:Net::HTTPHeader@Fields]:
  #
  #   req = Net::HTTP::Get.new(uri)
  #   req.add_field('Foo', 'bar')
  #   req['Foo']            # => "bar"
  #   req.add_field('Foo', 'baz')
  #   req['Foo']            # => "bar, baz"
  #   req.add_field('Foo', %w[baz bam])
  #   req['Foo']            # => "bar, baz, baz, bam"
  #   req.get_fields('Foo') # => ["bar", "baz", "baz", "bam"]
  #
  def add_field(key, val)
    stringified_downcased_key = key.downcase.to_s
    if @header.key?(stringified_downcased_key)
      append_field_value(@header[stringified_downcased_key], val)
    else
      set_field(key, val)
    end
  end

  private def set_field(key, val)
    case val
    when Enumerable
      ary = []
      append_field_value(ary, val)
      @header[key.downcase.to_s] = ary
    else
      val = val.to_s # for compatibility use to_s instead of to_str
      if val.b.count("\r\n") > 0
        raise ArgumentError, 'header field value cannot include CR/LF'
      end
      @header[key.downcase.to_s] = [val]
    end
  end

  private def append_field_value(ary, val)
    case val
    when Enumerable
      val.each{|x| append_field_value(ary, x)}
    else
      val = val.to_s
      if /[\r\n]/n.match?(val.b)
        raise ArgumentError, 'header field value cannot include CR/LF'
      end
      ary.push val
    end
  end

  # Returns the array field value for the given +key+,
  # or +nil+ if there is no such field;
  # see {Fields}[rdoc-ref:Net::HTTPHeader@Fields]:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res.get_fields('Connection') # => ["keep-alive"]
  #   res.get_fields('Nosuch')     # => nil
  #
  def get_fields(key)
    stringified_downcased_key = key.downcase.to_s
    return nil unless @header[stringified_downcased_key]
    @header[stringified_downcased_key].dup
  end

  # call-seq:
  #   fetch(key, default_val = nil) {|key| ... } -> object
  #   fetch(key, default_val = nil) -> value or default_val
  #
  # With a block, returns the string value for +key+ if it exists;
  # otherwise returns the value of the block;
  # ignores the +default_val+;
  # see {Fields}[rdoc-ref:Net::HTTPHeader@Fields]:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #
  #   # Field exists; block not called.
  #   res.fetch('Connection') do |value|
  #     fail 'Cannot happen'
  #   end # => "keep-alive"
  #
  #   # Field does not exist; block called.
  #   res.fetch('Nosuch') do |value|
  #     value.downcase
  #   end # => "nosuch"
  #
  # With no block, returns the string value for +key+ if it exists;
  # otherwise, returns +default_val+ if it was given;
  # otherwise raises an exception:
  #
  #   res.fetch('Connection', 'Foo') # => "keep-alive"
  #   res.fetch('Nosuch', 'Foo')     # => "Foo"
  #   res.fetch('Nosuch')            # Raises KeyError.
  #
  def fetch(key, *args, &block)   #:yield: +key+
    a = @header.fetch(key.downcase.to_s, *args, &block)
    a.kind_of?(Array) ? a.join(', ') : a
  end

  # Calls the block with each key/value pair:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res.each_header do |key, value|
  #     p [key, value] if key.start_with?('c')
  #   end
  #
  # Output:
  #
  #   ["content-type", "application/json; charset=utf-8"]
  #   ["connection", "keep-alive"]
  #   ["cache-control", "max-age=43200"]
  #   ["cf-cache-status", "HIT"]
  #   ["cf-ray", "771d17e9bc542cf5-ORD"]
  #
  # Returns an enumerator if no block is given.
  #
  # Net::HTTPHeader#each is an alias for Net::HTTPHeader#each_header.
  def each_header   #:yield: +key+, +value+
    block_given? or return enum_for(__method__) { @header.size }
    @header.each do |k,va|
      yield k, va.join(', ')
    end
  end

  alias each each_header

  # Calls the block with each field key:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res.each_key do |key|
  #     p key if key.start_with?('c')
  #   end
  #
  # Output:
  #
  #   "content-type"
  #   "connection"
  #   "cache-control"
  #   "cf-cache-status"
  #   "cf-ray"
  #
  # Returns an enumerator if no block is given.
  #
  # Net::HTTPHeader#each_name is an alias for Net::HTTPHeader#each_key.
  def each_name(&block)   #:yield: +key+
    block_given? or return enum_for(__method__) { @header.size }
    @header.each_key(&block)
  end

  alias each_key each_name

  # Calls the block with each capitalized field name:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res.each_capitalized_name do |key|
  #     p key if key.start_with?('C')
  #   end
  #
  # Output:
  #
  #   "Content-Type"
  #   "Connection"
  #   "Cache-Control"
  #   "Cf-Cache-Status"
  #   "Cf-Ray"
  #
  # The capitalization is system-dependent;
  # see {Case Mapping}[rdoc-ref:case_mapping.rdoc].
  #
  # Returns an enumerator if no block is given.
  def each_capitalized_name  #:yield: +key+
    block_given? or return enum_for(__method__) { @header.size }
    @header.each_key do |k|
      yield capitalize(k)
    end
  end

  # Calls the block with each string field value:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res.each_value do |value|
  #     p value if value.start_with?('c')
  #   end
  #
  # Output:
  #
  #   "chunked"
  #   "cf-q-config;dur=6.0000002122251e-06"
  #   "cloudflare"
  #
  # Returns an enumerator if no block is given.
  def each_value   #:yield: +value+
    block_given? or return enum_for(__method__) { @header.size }
    @header.each_value do |va|
      yield va.join(', ')
    end
  end

  # Removes the header for the given case-insensitive +key+
  # (see {Fields}[rdoc-ref:Net::HTTPHeader@Fields]);
  # returns the deleted value, or +nil+ if no such field exists:
  #
  #   req = Net::HTTP::Get.new(uri)
  #   req.delete('Accept') # => ["*/*"]
  #   req.delete('Nosuch') # => nil
  #
  def delete(key)
    @header.delete(key.downcase.to_s)
  end

  # Returns +true+ if the field for the case-insensitive +key+ exists, +false+ otherwise:
  #
  #   req = Net::HTTP::Get.new(uri)
  #   req.key?('Accept') # => true
  #   req.key?('Nosuch') # => false
  #
  def key?(key)
    @header.key?(key.downcase.to_s)
  end

  # Returns a hash of the key/value pairs:
  #
  #   req = Net::HTTP::Get.new(uri)
  #   req.to_hash
  #   # =>
  #   {"accept-encoding"=>["gzip;q=1.0,deflate;q=0.6,identity;q=0.3"],
  #    "accept"=>["*/*"],
  #    "user-agent"=>["Ruby"],
  #    "host"=>["jsonplaceholder.typicode.com"]}
  #
  def to_hash
    @header.dup
  end

  # Like #each_header, but the keys are returned in capitalized form.
  #
  # Net::HTTPHeader#canonical_each is an alias for Net::HTTPHeader#each_capitalized.
  def each_capitalized
    block_given? or return enum_for(__method__) { @header.size }
    @header.each do |k,v|
      yield capitalize(k), v.join(', ')
    end
  end

  alias canonical_each each_capitalized

  def capitalize(name)
    name.to_s.split(/-/).map {|s| s.capitalize }.join('-')
  end
  private :capitalize

  # Returns an array of Range objects that represent
  # the value of field <tt>'Range'</tt>,
  # or +nil+ if there is no such field;
  # see {Range request header}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#range-request-header]:
  #
  #   req = Net::HTTP::Get.new(uri)
  #   req['Range'] = 'bytes=0-99,200-299,400-499'
  #   req.range # => [0..99, 200..299, 400..499]
  #   req.delete('Range')
  #   req.range # # => nil
  #
  def range
    return nil unless @header['range']

    value = self['Range']
    # byte-range-set = *( "," OWS ) ( byte-range-spec / suffix-byte-range-spec )
    #   *( OWS "," [ OWS ( byte-range-spec / suffix-byte-range-spec ) ] )
    # corrected collected ABNF
    # http://tools.ietf.org/html/draft-ietf-httpbis-p5-range-19#section-5.4.1
    # http://tools.ietf.org/html/draft-ietf-httpbis-p5-range-19#appendix-C
    # http://tools.ietf.org/html/draft-ietf-httpbis-p1-messaging-19#section-3.2.5
    unless /\Abytes=((?:,[ \t]*)*(?:\d+-\d*|-\d+)(?:[ \t]*,(?:[ \t]*\d+-\d*|-\d+)?)*)\z/ =~ value
      raise Net::HTTPHeaderSyntaxError, "invalid syntax for byte-ranges-specifier: '#{value}'"
    end

    byte_range_set = $1
    result = byte_range_set.split(/,/).map {|spec|
      m = /(\d+)?\s*-\s*(\d+)?/i.match(spec) or
              raise Net::HTTPHeaderSyntaxError, "invalid byte-range-spec: '#{spec}'"
      d1 = m[1].to_i
      d2 = m[2].to_i
      if m[1] and m[2]
        if d1 > d2
          raise Net::HTTPHeaderSyntaxError, "last-byte-pos MUST greater than or equal to first-byte-pos but '#{spec}'"
        end
        d1..d2
      elsif m[1]
        d1..-1
      elsif m[2]
        -d2..-1
      else
        raise Net::HTTPHeaderSyntaxError, 'range is not specified'
      end
    }
    # if result.empty?
    # byte-range-set must include at least one byte-range-spec or suffix-byte-range-spec
    # but above regexp already denies it.
    if result.size == 1 && result[0].begin == 0 && result[0].end == -1
      raise Net::HTTPHeaderSyntaxError, 'only one suffix-byte-range-spec with zero suffix-length'
    end
    result
  end

  # call-seq:
  #   set_range(length) -> length
  #   set_range(offset, length) -> range
  #   set_range(begin..length) -> range
  #
  # Sets the value for field <tt>'Range'</tt>;
  # see {Range request header}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#range-request-header]:
  #
  # With argument +length+:
  #
  #   req = Net::HTTP::Get.new(uri)
  #   req.set_range(100)      # => 100
  #   req['Range']            # => "bytes=0-99"
  #
  # With arguments +offset+ and +length+:
  #
  #   req.set_range(100, 100) # => 100...200
  #   req['Range']            # => "bytes=100-199"
  #
  # With argument +range+:
  #
  #   req.set_range(100..199) # => 100..199
  #   req['Range']            # => "bytes=100-199"
  #
  # Net::HTTPHeader#range= is an alias for Net::HTTPHeader#set_range.
  def set_range(r, e = nil)
    unless r
      @header.delete 'range'
      return r
    end
    r = (r...r+e) if e
    case r
    when Numeric
      n = r.to_i
      rangestr = (n > 0 ? "0-#{n-1}" : "-#{-n}")
    when Range
      first = r.first
      last = r.end
      last -= 1 if r.exclude_end?
      if last == -1
        rangestr = (first > 0 ? "#{first}-" : "-#{-first}")
      else
        raise Net::HTTPHeaderSyntaxError, 'range.first is negative' if first < 0
        raise Net::HTTPHeaderSyntaxError, 'range.last is negative' if last < 0
        raise Net::HTTPHeaderSyntaxError, 'must be .first < .last' if first > last
        rangestr = "#{first}-#{last}"
      end
    else
      raise TypeError, 'Range/Integer is required'
    end
    @header['range'] = ["bytes=#{rangestr}"]
    r
  end

  alias range= set_range

  # Returns the value of field <tt>'Content-Length'</tt> as an integer,
  # or +nil+ if there is no such field;
  # see {Content-Length request header}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#content-length-request-header]:
  #
  #   res = Net::HTTP.get_response(hostname, '/nosuch/1')
  #   res.content_length # => 2
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res.content_length # => nil
  #
  def content_length
    return nil unless key?('Content-Length')
    len = self['Content-Length'].slice(/\d+/) or
        raise Net::HTTPHeaderSyntaxError, 'wrong Content-Length format'
    len.to_i
  end

  # Sets the value of field <tt>'Content-Length'</tt> to the given numeric;
  # see {Content-Length response header}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#content-length-response-header]:
  #
  #   _uri = uri.dup
  #   hostname = _uri.hostname           # => "jsonplaceholder.typicode.com"
  #   _uri.path = '/posts'               # => "/posts"
  #   req = Net::HTTP::Post.new(_uri)    # => #<Net::HTTP::Post POST>
  #   req.body = '{"title": "foo","body": "bar","userId": 1}'
  #   req.content_length = req.body.size # => 42
  #   req.content_type = 'application/json'
  #   res = Net::HTTP.start(hostname) do |http|
  #     http.request(req)
  #   end # => #<Net::HTTPCreated 201 Created readbody=true>
  #
  def content_length=(len)
    unless len
      @header.delete 'content-length'
      return nil
    end
    @header['content-length'] = [len.to_i.to_s]
  end

  # Returns +true+ if field <tt>'Transfer-Encoding'</tt>
  # exists and has value <tt>'chunked'</tt>,
  # +false+ otherwise;
  # see {Transfer-Encoding response header}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#transfer-encoding-response-header]:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res['Transfer-Encoding'] # => "chunked"
  #   res.chunked?             # => true
  #
  def chunked?
    return false unless @header['transfer-encoding']
    field = self['Transfer-Encoding']
    (/(?:\A|[^\-\w])chunked(?![\-\w])/i =~ field) ? true : false
  end

  # Returns a Range object representing the value of field
  # <tt>'Content-Range'</tt>, or +nil+ if no such field exists;
  # see {Content-Range response header}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#content-range-response-header]:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res['Content-Range'] # => nil
  #   res['Content-Range'] = 'bytes 0-499/1000'
  #   res['Content-Range'] # => "bytes 0-499/1000"
  #   res.content_range    # => 0..499
  #
  def content_range
    return nil unless @header['content-range']
    m = %r<\A\s*(\w+)\s+(\d+)-(\d+)/(\d+|\*)>.match(self['Content-Range']) or
        raise Net::HTTPHeaderSyntaxError, 'wrong Content-Range format'
    return unless m[1] == 'bytes'
    m[2].to_i .. m[3].to_i
  end

  # Returns the integer representing length of the value of field
  # <tt>'Content-Range'</tt>, or +nil+ if no such field exists;
  # see {Content-Range response header}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#content-range-response-header]:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res['Content-Range'] # => nil
  #   res['Content-Range'] = 'bytes 0-499/1000'
  #   res.range_length     # => 500
  #
  def range_length
    r = content_range() or return nil
    r.end - r.begin + 1
  end

  # Returns the {media type}[https://en.wikipedia.org/wiki/Media_type]
  # from the value of field <tt>'Content-Type'</tt>,
  # or +nil+ if no such field exists;
  # see {Content-Type response header}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#content-type-response-header]:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res['content-type'] # => "application/json; charset=utf-8"
  #   res.content_type    # => "application/json"
  #
  def content_type
    return nil unless main_type()
    if sub_type()
    then "#{main_type()}/#{sub_type()}"
    else main_type()
    end
  end

  # Returns the leading ('type') part of the
  # {media type}[https://en.wikipedia.org/wiki/Media_type]
  # from the value of field <tt>'Content-Type'</tt>,
  # or +nil+ if no such field exists;
  # see {Content-Type response header}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#content-type-response-header]:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res['content-type'] # => "application/json; charset=utf-8"
  #   res.main_type       # => "application"
  #
  def main_type
    return nil unless @header['content-type']
    self['Content-Type'].split(';').first.to_s.split('/')[0].to_s.strip
  end

  # Returns the trailing ('subtype') part of the
  # {media type}[https://en.wikipedia.org/wiki/Media_type]
  # from the value of field <tt>'Content-Type'</tt>,
  # or +nil+ if no such field exists;
  # see {Content-Type response header}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#content-type-response-header]:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res['content-type'] # => "application/json; charset=utf-8"
  #   res.sub_type        # => "json"
  #
  def sub_type
    return nil unless @header['content-type']
    _, sub = *self['Content-Type'].split(';').first.to_s.split('/')
    return nil unless sub
    sub.strip
  end

  # Returns the trailing ('parameters') part of the value of field <tt>'Content-Type'</tt>,
  # or +nil+ if no such field exists;
  # see {Content-Type response header}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#content-type-response-header]:
  #
  #   res = Net::HTTP.get_response(hostname, '/todos/1')
  #   res['content-type'] # => "application/json; charset=utf-8"
  #   res.type_params     # => {"charset"=>"utf-8"}
  #
  def type_params
    result = {}
    list = self['Content-Type'].to_s.split(';')
    list.shift
    list.each do |param|
      k, v = *param.split('=', 2)
      result[k.strip] = v.strip
    end
    result
  end

  # Sets the value of field <tt>'Content-Type'</tt>;
  # returns the new value;
  # see {Content-Type request header}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#content-type-request-header]:
  #
  #   req = Net::HTTP::Get.new(uri)
  #   req.set_content_type('application/json') # => ["application/json"]
  #
  # Net::HTTPHeader#content_type= is an alias for Net::HTTPHeader#set_content_type.
  def set_content_type(type, params = {})
    @header['content-type'] = [type + params.map{|k,v|"; #{k}=#{v}"}.join('')]
  end

  alias content_type= set_content_type

  # Set header fields and a body from HTML form data.
  # +params+ should be an Array of Arrays or
  # a Hash containing HTML form data.
  # Optional argument +sep+ means data record separator.
  #
  # Values are URL encoded as necessary and the content-type is set to
  # application/x-www-form-urlencoded
  #
  # Example:
  #
  #    http.form_data = {"q" => "ruby", "lang" => "en"}
  #    http.form_data = {"q" => ["ruby", "perl"], "lang" => "en"}
  #    http.set_form_data({"q" => "ruby", "lang" => "en"}, ';')
  #
  # Net::HTTPHeader#form_data= is an alias for Net::HTTPHeader#set_form_data.
  def set_form_data(params, sep = '&')
    query = URI.encode_www_form(params)
    query.gsub!(/&/, sep) if sep != '&'
    self.body = query
    self.content_type = 'application/x-www-form-urlencoded'
  end

  alias form_data= set_form_data

  # Set an HTML form data set.
  # +params+ :: The form data to set, which should be an enumerable.
  #             See below for more details.
  # +enctype+ :: The content type to use to encode the form submission,
  #              which should be application/x-www-form-urlencoded or
  #              multipart/form-data.
  # +formopt+ :: An options hash, supporting the following options:
  #              :boundary :: The boundary of the multipart message. If
  #                           not given, a random boundary will be used.
  #              :charset :: The charset of the form submission. All
  #                          field names and values of non-file fields
  #                          should be encoded with this charset.
  #
  # Each item of params should respond to +each+ and yield 2-3 arguments,
  # or an array of 2-3 elements. The arguments yielded should be:
  #
  # - The name of the field.
  # - The value of the field, it should be a String or a File or IO-like.
  # - An options hash, supporting the following options
  #   (used only for file uploads); entries:
  #
  #   - +:filename+: The name of the file to use.
  #   - +:content_type+: The content type of the uploaded file.
  #
  # Each item is a file field or a normal field.
  # If +value+ is a File object or the +opt+ hash has a :filename key,
  # the item is treated as a file field.
  #
  # If Transfer-Encoding is set as chunked, this sends the request using
  # chunked encoding. Because chunked encoding is HTTP/1.1 feature,
  # you should confirm that the server supports HTTP/1.1 before using
  # chunked encoding.
  #
  # Example:
  #
  #    req.set_form([["q", "ruby"], ["lang", "en"]])
  #
  #    req.set_form({"f"=>File.open('/path/to/filename')},
  #                 "multipart/form-data",
  #                 charset: "UTF-8",
  #    )
  #
  #    req.set_form([["f",
  #                   File.open('/path/to/filename.bar'),
  #                   {filename: "other-filename.foo"}
  #                 ]],
  #                 "multipart/form-data",
  #    )
  #
  # See also RFC 2388, RFC 2616, HTML 4.01, and HTML5
  #
  def set_form(params, enctype='application/x-www-form-urlencoded', formopt={})
    @body_data = params
    @body = nil
    @body_stream = nil
    @form_option = formopt
    case enctype
    when /\Aapplication\/x-www-form-urlencoded\z/i,
      /\Amultipart\/form-data\z/i
      self.content_type = enctype
    else
      raise ArgumentError, "invalid enctype: #{enctype}"
    end
  end

  # Set the Authorization: header for "Basic" authorization.
  def basic_auth(account, password)
    @header['authorization'] = [basic_encode(account, password)]
  end

  # Set Proxy-Authorization: header for "Basic" authorization.
  def proxy_basic_auth(account, password)
    @header['proxy-authorization'] = [basic_encode(account, password)]
  end

  def basic_encode(account, password)
    'Basic ' + ["#{account}:#{password}"].pack('m0')
  end
  private :basic_encode

  def connection_close?
    token = /(?:\A|,)\s*close\s*(?:\z|,)/i
    @header['connection']&.grep(token) {return true}
    @header['proxy-connection']&.grep(token) {return true}
    false
  end

  def connection_keep_alive?
    token = /(?:\A|,)\s*keep-alive\s*(?:\z|,)/i
    @header['connection']&.grep(token) {return true}
    @header['proxy-connection']&.grep(token) {return true}
    false
  end

end
