=begin

= net/imap.rb

Copyright (C) 2000  Shugo Maeda <shugo@ruby-lang.org>

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.

== class Net::IMAP

Net::IMAP implements Internet Message Access Protocol (IMAP) clients.

=== Super Class

Object

=== Class Methods

: new(host, port = 143)
      Creates a new Net::IMAP object and connects it to the specified
      port on the named host.

: debug
      Returns the debug mode

: debug = val
      Sets the debug mode

: add_authenticator(auth_type, authenticator)
      Adds an authenticator for Net::IMAP#authenticate.

=== Methods

: greeting
      Returns an initial greeting response from the server.

: responses
      Returns recorded untagged responses.

      ex).
        imap.select("inbox")
        p imap.responses["EXISTS"][-1]
        #=> [2]
        p imap.responses["UIDVALIDITY"][-1]
        #=> [968263756]

: disconnect
      Disconnects from the server.

: capability
      Sends a CAPABILITY command, and returns a listing of
      capabilities that the server supports.

: noop
      Sends a NOOP command to the server. It does nothing.

: logout
      Sends a LOGOUT command to inform the server that the client is
      done with the connection.

: authenticate(auth_type, arg...)
      Sends an AUTEHNTICATE command to authenticate the client.
      The auth_type parameter is a string that represents
      the authentication mechanism to be used. Currently Net::IMAP
      supports "LOGIN" and "CRAM-MD5" for the auth_type.

      ex).
        imap.authenticate('LOGIN', user, password)

: login(user, password)
      Sends a LOGIN command to identify the client and carries
      the plaintext password authenticating this user.

: select(mailbox)
      Sends a SELECT command to select a mailbox so that messages
      in the mailbox can be accessed.

: examine(mailbox)
      Sends a EXAMINE command to select a mailbox so that messages
      in the mailbox can be accessed. However, the selected mailbox
      is identified as read-only.

: create(mailbox)
      Sends a CREATE command to create a new mailbox.

: delete(mailbox)
      Sends a DELETE command to remove the mailbox.

: rename(mailbox, newname)
      Sends a RENAME command to change the name of the mailbox to
      the newname.

: subscribe(mailbox)
      Sends a SUBSCRIBE command to add the specified mailbox name to
      the server's set of "active" or "subscribed" mailboxes.

: unsubscribe(mailbox)
      Sends a UNSUBSCRIBE command to remove the specified mailbox name
      from the server's set of "active" or "subscribed" mailboxes.

: list(refname, mailbox)
      Sends a LIST command, and returns a subset of names from
      the complete set of all names available to the client.

      ex).
        imap.create("foo/bar")
        imap.create("foo/baz")
        p imap.list("", "foo/%")
        #=> [[[:NoSelect], "/", "foo/"], [[:NoInferiors], "/", "foo/baz"], [[:NoInferiors], "/", "foo/bar"]]

: lsub(refname, mailbox)
      Sends a LSUB command, and returns a subset of names from the set
      of names that the user has declared as being "active" or
      "subscribed".

: status(mailbox, attr)
      Sends a STATUS command, and returns the status of the indicated
      mailbox.

      ex).
        p imap.status("inbox", ["MESSAGES", "RECENT"])
        #=> {"RECENT"=>0, "MESSAGES"=>5}

: append(mailbox, message, flags = nil, date_time = nil)
      Sends a APPEND command to append the message to the end of
      the mailbox.

      ex).
        imap.append("inbox", <<EOF.gsub(/\n/, "\r\n"), [:Seen], Time.now)
        Subject: hello
        From: shugo@ruby-lang.org
        To: shugo@ruby-lang.org
        
        hello world
        EOF

: check
      Sends a CHECK command to request a checkpoint of the currently
      selected mailbox.

: close
      Sends a CLOSE command to close the currently selected mailbox.
      The CLOSE command permanently removes from the mailbox all
      messages that have the \Deleted flag set.

: expunge
      Sends a EXPUNGE command to permanently remove from the currently
      selected mailbox all messages that have the \Deleted flag set.

: search(keys, charset = nil)
: uid_search(keys, charset = nil)
      Sends a SEARCH command to search the mailbox for messages that
      match the given searching criteria, and returns message sequence
      numbers (search) or unique identifiers (uid_search).

      ex).
        p imap.search(["SUBJECT", "hello"])
        #=> [1, 6, 7, 8]

: fetch(set, attr)
: uid_fetch(set, attr)
      Sends a FETCH command to retrieve data associated with a message
      in the mailbox. the set parameter is a number or an array of
      numbers or a Range object. the number is a message sequence
      number (fetch) or a unique identifier (uid_fetch).

      ex).
        p imap.fetch(6..-1, "UID")
        #=> [[6, {"UID"=>28}], [7, {"UID"=>29}], [8, {"UID"=>30}]]

: store(set, attr, flags)
: uid_store(set, attr, flags)
      Sends a STORE command to alter data associated with a message
      in the mailbox. the set parameter is a number or an array of
      numbers or a Range object. the number is a message sequence
      number (store) or a unique identifier (uid_store).

      ex).
        p imap.store(6..-1, "+FLAGS", [:Deleted])
        #=> [[6, {"FLAGS"=>[:Deleted]}], [7, {"FLAGS"=>[:Seen, :Deleted]}], [8, {"FLAGS"=>[:Seen, :Deleted]}]]

: copy(set, mailbox)
: uid_copy(set, mailbox)
      Sends a COPY command to copy the specified message(s) to the end
      of the specified destination mailbox. the set parameter is
      a number or an array of numbers or a Range object. the number is
      a message sequence number (copy) or a unique identifier (uid_copy).

: sort(sort_keys, search_keys, charset)
: uid_sort(sort_keys, search_keys, charset)
      Sends a SORT command to sort messages in the mailbox.

      ex).
        p imap.sort(["FROM"], ["ALL"], "US-ASCII")
        #=> [1, 2, 3, 5, 6, 7, 8, 4, 9]
        p imap.sort(["DATE"], ["SUBJECT", "hello"], "US-ASCII")
        #=> [6, 7, 8, 1]

=end

require "socket"
require "md5"

module Net
  class IMAP
    attr_reader :greeting, :responses

    def self.debug
      return @@debug
    end

    def self.debug=(val)
      return @@debug = val
    end

    def self.add_authenticator(auth_type, authenticator)
      @@authenticators[auth_type] = authenticator
    end

    def disconnect
      @sock.close
    end

    def capability
      send_command("CAPABILITY")
      return @responses.delete("CAPABILITY")[-1]
    end

    def noop
      send_command("NOOP")
    end

    def logout
      send_command("LOGOUT")
    end

    def authenticate(auth_type, *args)
      auth_type = auth_type.upcase
      unless @@authenticators.has_key?(auth_type)
	raise ArgumentError,
	  format('unknown auth type - "%s"', auth_type)
      end
      authenticator = @@authenticators[auth_type].new(*args)
      send_command("AUTHENTICATE", auth_type) do |resp|
	if resp.prefix == "+"
	  data = authenticator.process(resp[0].unpack("m")[0])
	  send_data([data].pack("m").chomp)
	end
      end
    end

    def login(user, password)
      send_command("LOGIN", user, password)
    end

    def select(mailbox)
      @responses.clear
      send_command("SELECT", mailbox)
    end

    def examine(mailbox)
      @responses.clear
      send_command("EXAMINE", mailbox)
    end

    def create(mailbox)
      send_command("CREATE", mailbox)
    end

    def delete(mailbox)
      send_command("DELETE", mailbox)
    end

    def rename(mailbox, newname)
      send_command("RENAME", mailbox, newname)
    end

    def subscribe(mailbox)
      send_command("SUBSCRIBE", mailbox)
    end

    def unsubscribe(mailbox)
      send_command("UNSUBSCRIBE", mailbox)
    end

    def list(refname, mailbox)
      send_command("LIST", refname, mailbox)
      return @responses.delete("LIST")
    end

    def lsub(refname, mailbox)
      send_command("LSUB", refname, mailbox)
      return @responses.delete("LSUB")
    end

    def status(mailbox, attr)
      send_command("STATUS", mailbox, attr)
      status_list = @responses.delete("STATUS")[-1][1]
      return Hash[*status_list]
    end

    def append(mailbox, message, flags = nil, date_time = nil)
      args = []
      if flags
	flags.collect! {|i| Flag.new(i)}
	args.push(flags)
      end
      args.push(date_time) if date_time
      args.push(Literal.new(message))
      send_command("APPEND", mailbox, *args)
    end

    def check
      send_command("CHECK")
    end

    def close
      send_command("CLOSE")
    end

    def expunge
      send_command("EXPUNGE")
      return @responses.delete("EXPUNGE").collect {|i| i[0]}
    end

    def search(keys, charset = nil)
      return search_internal("SEARCH", keys, charset)
    end

    def uid_search(keys, charset = nil)
      return search_internal("UID SEARCH", keys, charset)
    end

    def fetch(set, attr)
      return fetch_internal("FETCH", set, attr)
    end

    def uid_fetch(set, attr)
      return fetch_internal("UID FETCH", set, attr)
    end

    def store(set, attr, flags)
      return store_internal("STORE", set, attr, flags)
    end

    def uid_store(set, attr, flags)
      return store_internal("UID STORE", set, attr, flags)
    end

    def copy(set, mailbox)
      copy_internal("COPY", set, mailbox)
    end

    def uid_copy(set, mailbox)
      copy_internal("UID COPY", set, mailbox)
    end

    def sort(sort_keys, search_keys, charset)
      return sort_internal("SORT", sort_keys, search_keys, charset)
    end

    def uid_sort(sort_keys, search_keys, charset)
      return sort_internal("UID SORT", sort_keys, search_keys, charset)
    end

    private

    CRLF = "\r\n"
    PORT = 143

    @@debug = false
    @@authenticators = {}

    def initialize(host, port = PORT)
      @host = host
      @port = port
      @tag_prefix = "RUBY"
      @tagno = 0
      @parser = ResponseParser.new
      @sock = TCPSocket.open(host, port)
      @responses = Hash.new([].freeze)
      @greeting = get_response
      if @greeting.name == "BYE"
	@sock.close
	raise ByeResponseError, resp[0]
      end
    end

    def send_command(cmd, *args, &block)
      tag = generate_tag
      data = args.collect {|i| format_data(i)}.join(" ")
      if data.length > 0
	put_line(tag + " " + cmd + " " + data)
      else
	put_line(tag + " " + cmd)
      end
      return get_all_responses(tag, cmd, &block)
    end

    def generate_tag
      @tagno += 1
      return format("%s%04d", @tag_prefix, @tagno)
    end

    def send_data(*args)
      data = args.collect {|i| format_data(i)}.join(" ")
      put_line(data)
    end

    def put_line(line)
      line = line + CRLF
      @sock.print(line)
      if @@debug
        $stderr.print(line.gsub(/^/n, "C: "))
      end
    end

    def get_all_responses(tag, cmd, &block)
      while resp = get_response
	if @@debug
	  $stderr.puts(resp.inspect)
	end
	if resp.prefix == tag
	  case resp.name
	  when "NO"
	    raise NoResponseError, resp[0]
	  when "BAD"
	    raise BadResponseError, resp[0]
	  else
	    return resp
	  end
	else
	  if resp.prefix == "*"
	    if resp.name == "BYE" &&
		cmd != "LOGOUT"
	      raise ByeResponseError, resp[0]
	    end
	    record_response(resp.name, resp.data)
	    if /\A(OK|NO|BAD)\z/n =~ resp.name &&
		resp[0].instance_of?(Array)
	      record_response(resp[0][0], resp[0][1..-1])
	    end
	  end
	  block.call(resp) if block
	end
      end
    end

    def get_response
      buff = ""
      while true
	s = @sock.gets(CRLF)
	break unless s
	buff.concat(s)
	if /\{(\d+)\}\r\n/n =~ s
	  s = @sock.read($1.to_i)
	  buff.concat(s)
	else
	  break
	end
      end
      return nil if buff.length == 0
      if @@debug
        $stderr.print(buff.gsub(/^/n, "S: "))
      end
      return @parser.parse(buff)
    end

    def record_response(name, data)
      unless @responses.has_key?(name)
	@responses[name] = []
      end
      @responses[name].push(data)
    end

    def format_data(data)
      case data
      when nil
	return "NIL"
      when String
	return format_string(data)
      when Integer
	return format_number(data)
      when Array
	return format_list(data)
      when Time
	return format_time(data)
      when Symbol
	return format_symbol(data)
      else
	return data.format_data
      end
    end

    def format_string(str)
      case str
      when ""
	return '""'
      when /[\r\n]/n
	# literal
	return "{" + str.length.to_s + "}" + CRLF + str
      when /[(){ \x00-\x1f\x7f%*"\\]/n
	# quoted string
	return '"' + str.gsub(/["\\]/n, "\\\\\\&") + '"'
      else
	# atom
	return str
      end
    end

    def format_number(num)
      if num < 0 || num >= 4294967296
	raise DataFormatError, num.to_s
      end
      return num.to_s
    end

    def format_list(list)
      contents = list.collect {|i| format_data(i)}.join(" ")
      return "(" + contents + ")"
    end

    DATE_MONTH = %w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

    def format_time(time)
      t = time.dup.gmtime
      return format('"%2d-%3s-%4d %02d:%02d:%02d +0000"',
		    t.day, DATE_MONTH[t.month - 1], t.year,
		    t.hour, t.min, t.sec)
    end

    def format_symbol(symbol)
      return "\\" + symbol.to_s
    end

    def search_internal(cmd, keys, charset)
      normalize_searching_criteria(keys)
      if charset
	send_command(cmd, "CHARSET", charset, *keys)
      else
	send_command(cmd, *keys)
      end
      return @responses.delete("SEARCH")[-1]
    end

    def fetch_internal(cmd, set, attr)
      send_command(cmd, MessageSet.new(set), attr)
      return get_fetch_response
    end

    def store_internal(cmd, set, attr, flags)
      send_command(cmd, MessageSet.new(set), attr, flags)
      return get_fetch_response
    end

    def copy_internal(cmd, set, mailbox)
      send_command(cmd, MessageSet.new(set), mailbox)
    end

    def sort_internal(cmd, sort_keys, search_keys, charset)
      normalize_searching_criteria(search_keys)
      send_command(cmd, sort_keys, charset, *search_keys)
      return @responses.delete("SORT")[-1]
    end

    def normalize_searching_criteria(keys)
      keys.collect! do |i|
	case i
	when -1, Range, Array
	  MessageSet.new(i)
	else
	  i
	end
      end
    end

    def get_fetch_response
      return @responses.delete("FETCH").collect { |i|
	i[1] = Hash[*i[1]]
	i
      }
    end

    class Atom
      def format_data
	return @data
      end

      private

      def initialize(data)
	@data = data
      end
    end

    class QuotedString
      def format_data
	return '"' + @data.gsub(/["\\]/n, "\\\\\\&") + '"'
      end

      private

      def initialize(data)
	@data = data
      end
    end

    class Literal
      def format_data
	return "{" + @data.length.to_s + "}" + CRLF + @data
      end

      private

      def initialize(data)
	@data = data
      end
    end

    class MessageSet
      def format_data
	return format_internal(@data)
      end

      private

      def initialize(data)
	@data = data
      end

      def format_internal(data)
	case data
	when "*"
	  return data
	when Integer
	  ensure_nz_number(data)
	  if data == -1
	    return "*"
	  else
	    return data.to_s
	  end
	when Range
	  return format_internal(data.first) +
	    ":" + format_internal(data.last)
	when Array
	  return data.collect {|i| format_internal(i)}.join(",")
	else
	  raise DataFormatError, data.inspect
	end
      end

      def ensure_nz_number(num)
	if num < -1 || num == 0 || num >= 4294967296
	  raise DataFormatError, num.inspect
	end
      end
    end

    class Response
      attr_reader :prefix, :name, :data, :raw_data

      def inspect
	s = @data.collect{|i| i.inspect}.join(" ")
	if @name
	  return "#<Response: " + @prefix + " " + @name + " " + s + ">"
	else
	  return "#<Response: " + @prefix + " " + s + ">"
	end
      end

      def method_missing(mid, *args)
	return @data.send(mid, *args)
      end

      private

      def initialize(prefix, data, raw_data)
	@prefix = prefix
	if prefix == "+"
	  @name = nil
	else
	  data.each_with_index do |item, i|
	    if item.instance_of?(String)
	      @name = item
	      data.delete_at(i)
	      break
	    end
	  end
	end
	@data = data
	@raw_data = raw_data
      end
    end

    class ResponseParser
      def parse(str)
	@str = str
	@pos = 0
	@lex_state = EXPR_DATA
	@token.symbol = nil
	return parse_response
      end

      private

      EXPR_DATA		= :DATA
      EXPR_TEXT		= :TEXT
      EXPR_CODE		= :CODE
      EXPR_CODE_TEXT	= :CODE_TEXT

      T_NIL	= :NIL
      T_NUMBER	= :NUMBER
      T_ATOM	= :ATOM
      T_QUOTED	= :QUOTED
      T_LITERAL	= :LITERAL
      T_FLAG	= :FLAG
      T_LPAREN	= :LPAREN
      T_RPAREN	= :RPAREN
      T_STAR	= :STAR
      T_CRLF	= :CRLF
      T_EOF	= :EOF
      T_LBRA	= :LBRA
      T_RBRA	= :RBRA
      T_TEXT	= :TEXT

      DATA_REGEXP = /\G *(?:\
(?# 1:	NIL	)(NIL)|\
(?# 2:	NUMBER	)(\d+)|\
(?# 3:	ATOM	)([^(){ \x00-\x1f\x7f%*"\\]+)|\
(?# 4:	QUOTED	)"((?:[^"\\]|\\["\\])*)"|\
(?# 5:	LITERAL	)\{(\d+)\}\r\n|\
(?# 6:	FLAG	)(\\(?:[^(){ \x00-\x1f\x7f%*"\\]+|\*))|\
(?# 7:	LPAREN	)(\()|\
(?# 8:	RPAREN	)(\))|\
(?# 9:	STAR	)(\*)|\
(?# 10:	CRLF	)(\r\n)|\
(?# 11:	EOF	)(\z))/ni

      CODE_REGEXP = /\G *(?:\
(?# 1:	NUMBER	)(\d+)|\
(?# 2:	ATOM	)([^(){ \x00-\x1f\x7f%*"\\\[\]]+)|\
(?# 3:	FLAG	)(\\(?:[^(){ \x00-\x1f\x7f%*"\\]+|\*))|\
(?# 4:	LPAREN	)(\()|\
(?# 5:	RPAREN	)(\))|\
(?# 6:	LBRA	)(\[)|\
(?# 7:	RBRA	)(\]))/ni

      CODE_TEXT_REGEXP = /\G *(?:\
(?# 1:	TEXT	)([^\r\n\]]*))/ni

      TEXT_REGEXP = /\G *(?:\
(?# 1:	LBRA	)(\[)|\
(?# 2:	TEXT	)([^\r\n]*))/ni

      Token = Struct.new("Token", :symbol, :value)

      def initialize
	@token = Token.new(nil, nil)
      end

      def parse_response
	prefix = parse_prefix
	case prefix
	when "+"
	  data = parse_resp_text
	when "*"
	  data = parse_response_data
	else
	  data = parse_response_cond
	end
	match_token(T_CRLF)
	match_token(T_EOF)
	return Response.new(prefix, data, @str)
      end

      def parse_prefix
	token = match_token(T_STAR, T_ATOM)
	return token.value
      end

      def parse_resp_text
	val = []
	@lex_state = EXPR_TEXT
	token = get_token
	if token.symbol == T_LBRA
	  val.push(parse_resp_text_code)
	end
	val.push(parse_text)
	@lex_state = EXPR_DATA
	return val
      end

      def parse_resp_text_code
	val = []
	@lex_state = EXPR_CODE
	match_token(T_LBRA)
	token = match_token(T_ATOM)
	val.push(token.value)
	case token.value
	when /\A(ALERT|PARSE|READ-ONLY|READ-WRITE|TRYCREATE)\z/n
	  # do nothing
	when /\A(PERMANENTFLAGS)\z/n
	  token = get_token
	  if token.symbol != T_LPAREN
	    parse_error('unexpected token %s (expected "(")',
			token.symbol.id2name)
	  end
	  val.push(parse_parenthesized_list)
	when /\A(UIDVALIDITY|UIDNEXT|UNSEEN)\z/n
	  token = match_token(T_NUMBER)
	  val.push(token.value)
	else
	  @lex_state = EXPR_CODE_TEXT
	  val.push(parse_text)
	  @lex_state = EXPR_CODE
	end
	match_token(T_RBRA)
	@lex_state = EXPR_TEXT
	return val
      end

      def parse_text
	token = match_token(T_TEXT)
	return token.value
      end

      def parse_response_data
	token = get_token
	if token.symbol == T_ATOM &&
	    /\A(OK|NO|BAD|PREAUTH|BYE)\z/n =~ token.value
	  return parse_response_cond
	else
	  return parse_data_list
	end
      end

      def parse_response_cond
	val = []
	token = match_token(T_ATOM)
	val.push(token.value)
	val += parse_resp_text
	return val
      end

      def parse_data_list
	val = []
	while true
	  token = get_token
	  case token.symbol
	  when T_EOF
	    parse_error('unexpected token %s', token.symbol.id2name)
	  when T_CRLF, T_RPAREN
	    return val
	  when T_LPAREN
	    val.push(parse_parenthesized_list)
	  else
	    val.push(token.value)
	    @token.symbol = nil
	  end
	end
      end

      def parse_parenthesized_list
	match_token(T_LPAREN)
	val = parse_data_list
	match_token(T_RPAREN)
	return val
      end

      def match_token(*args)
	token = get_token
	unless args.include?(token.symbol)
	  parse_error('unexpected token %s (expected %s)',
		      token.symbol.id2name,
		      args.collect {|i| i.id2name}.join(" or "))
	end
	@token.symbol = nil
	return token
      end

      def get_token
	unless @token.symbol
	  next_token
	end
	return @token
      end

      def next_token
	case @lex_state
	when EXPR_DATA
	  if @str.index(DATA_REGEXP, @pos)
	    @pos = $~.end(0)
	    if $1
	      @token.value = nil
	      @token.symbol = T_NIL
	    elsif $2
	      @token.value = $+.to_i
	      @token.symbol = T_NUMBER
	    elsif $3
	      @token.value = $+.upcase
	      @token.symbol = T_ATOM
	    elsif $4
	      @token.value = $+.gsub(/\\(["\\])/n, "\\1")
	      @token.symbol = T_QUOTED
	    elsif $5
	      len = $+.to_i
	      @token.value = @str[@pos, len]
	      @pos += len
	      @token.symbol = T_LITERAL
	    elsif $6
	      @token.value = $+[1..-1].intern
	      @token.symbol = T_FLAG
	    elsif $7
	      @token.value = nil
	      @token.symbol = T_LPAREN
	    elsif $8
	      @token.value = nil
	      @token.symbol = T_RPAREN
	    elsif $9
	      @token.value = $+
	      @token.symbol = T_STAR
	    elsif $10
	      @token.value = nil
	      @token.symbol = T_CRLF
	    elsif $11
	      @token.value = nil
	      @token.symbol = T_EOF
	    else
	      parse_error("[BUG] DATA_REGEXP is invalid")
	    end
	    return
	  end
	when EXPR_TEXT
	  if @str.index(TEXT_REGEXP, @pos)
	    @pos = $~.end(0)
	    if $1
	      @token.value = nil
	      @token.symbol = T_LBRA
	    elsif $2
	      @token.value = $+
	      @token.symbol = T_TEXT
	    else
	      parse_error("[BUG] TEXT_REGEXP is invalid")
	    end
	    return
	  end
	when EXPR_CODE
	  if @str.index(CODE_REGEXP, @pos)
	    @pos = $~.end(0)
	    if $1
	      @token.value = $+.to_i
	      @token.symbol = T_NUMBER
	    elsif $2
	      @token.value = $+.upcase
	      @token.symbol = T_ATOM
	    elsif $3
	      @token.value = $+[1..-1].capitalize.intern
	      @token.symbol = T_FLAG
	    elsif $4
	      @token.value = nil
	      @token.symbol = T_LPAREN
	    elsif $5
	      @token.value = nil
	      @token.symbol = T_RPAREN
	    elsif $6
	      @token.value = nil
	      @token.symbol = T_LBRA
	    elsif $7
	      @token.value = nil
	      @token.symbol = T_RBRA
	    else
	      parse_error("[BUG] CODE_REGEXP is invalid")
	    end
	    return
	  end
	when EXPR_CODE_TEXT
	  if @str.index(CODE_TEXT_REGEXP, @pos)
	    @pos = $~.end(0)
	    if $1
	      @token.value = $+
	      @token.symbol = T_TEXT
	    else
	      parse_error("[BUG] CODE_TEXT_REGEXP is invalid")
	    end
	    return
	  end
	else
	  parse_error("illegal @lex_state - %s", @lex_state.inspect)
	end
	@str.index(/\S*/n, @pos)
	parse_error("unknown token - %s", $&.dump)
      end

      def parse_error(fmt, *args)
	if IMAP.debug
	  $stderr.printf("@str: %s\n", @str.dump)
	  $stderr.printf("@pos: %d\n", @pos)
	  $stderr.printf("@lex_state: %s\n", @lex_state.inspect)
	  if @token.symbol
	    $stderr.printf("@token.symbol: %s\n", @token.symbol.id2name)
	    $stderr.printf("@token.value: %s\n", @token.value.inspect)
	  end
	end
	raise ResponseParseError, format(fmt, *args)
      end
    end

    class LoginAuthenticator
      def process(data)
	case @state
	when STATE_USER
	  @state = STATE_PASSWORD
	  return @user
	when STATE_PASSWORD
	  return @password
	end
      end

      private

      STATE_USER = :USER
      STATE_PASSWORD = :PASSWORD

      def initialize(user, password)
	@user = user
	@password = password
	@state = STATE_USER
      end
    end
    add_authenticator "LOGIN", LoginAuthenticator

    class CramMD5Authenticator
      def process(challenge)
	digest = hmac_md5(challenge, @password)
	return @user + " " + digest
      end

      private

      def initialize(user, password)
	@user = user
	@password = password
      end

      def hmac_md5(text, key)
	if key.length > 64
	  md5 = MD5.new(key)
	  key = md5.digest
	end

	k_ipad = key + "\0" * (64 - key.length)
	k_opad = key + "\0" * (64 - key.length)
	for i in 0..63
	  k_ipad[i] ^= 0x36
	  k_opad[i] ^= 0x5c
	end

	md5 = MD5.new
	md5.update(k_ipad)
	md5.update(text)
	digest = md5.digest

	md5 = MD5.new
	md5.update(k_opad)
	md5.update(digest)
	return md5.hexdigest
      end
    end
    add_authenticator "CRAM-MD5", CramMD5Authenticator

    class Error < StandardError
    end

    class DataFormatError < Error
    end

    class ResponseParseError < Error
    end

    class ResponseError < Error
    end

    class NoResponseError < ResponseError
    end

    class BadResponseError < ResponseError
    end

    class ByeResponseError < ResponseError
    end
  end
end
