=begin

= net/imap.rb

Copyright (C) 2000  Shugo Maeda <shugo@ruby-lang.org>

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.

== Net::IMAP

Net::IMAP implements Internet Message Access Protocol (IMAP) clients.
(The protocol is described in ((<[IMAP]>)).)

=== Super Class

Object

=== Class Methods

: new(host, port = 143)
      Creates a new Net::IMAP object and connects it to the specified
      port on the named host.

: debug
      Returns the debug mode.

: debug = val
      Sets the debug mode.

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
        #=> 2
        p imap.responses["UIDVALIDITY"][-1]
        #=> 968263756

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
      The return value is an array of ((<Net::IMAP::MailboxList>)).

      ex).
        imap.create("foo/bar")
        imap.create("foo/baz")
        p imap.list("", "foo/%")
        #=> [#<Net::IMAP::MailboxList attr=[:Noselect], delim="/", name="foo/">, #<Net::IMAP::MailboxList attr=[:Noinferiors, :Marked], delim="/", name="foo/bar">, #<Net::IMAP::MailboxList attr=[:Noinferiors], delim="/", name="foo/baz">]

: lsub(refname, mailbox)
      Sends a LSUB command, and returns a subset of names from the set
      of names that the user has declared as being "active" or
      "subscribed".
      The return value is an array of ((<Net::IMAP::MailboxList>)).

: status(mailbox, attr)
      Sends a STATUS command, and returns the status of the indicated
      mailbox.
      The return value is a hash of attributes.

      ex).
        p imap.status("inbox", ["MESSAGES", "RECENT"])
        #=> {"RECENT"=>0, "MESSAGES"=>44}

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
        p imap.search('SUBJECT "hello"')
        #=> [1, 6, 7, 8]

: fetch(set, attr)
: uid_fetch(set, attr)
      Sends a FETCH command to retrieve data associated with a message
      in the mailbox. the set parameter is a number or an array of
      numbers or a Range object. the number is a message sequence
      number (fetch) or a unique identifier (uid_fetch).
      The return value is an array of ((<Net::IMAP::FetchData>)).

      ex).
        p imap.fetch(6..8, "UID")
        #=> [#<Net::IMAP::FetchData seqno=6, attr={"UID"=>98}>, #<Net::IMAP::FetchData seqno=7, attr={"UID"=>99}>, #<Net::IMAP::FetchData seqno=8, attr={"UID"=>100}>]
        p imap.fetch(6, "BODY[HEADER.FIELDS (SUBJECT)]")
        #=> [#<Net::IMAP::FetchData seqno=6, attr={"BODY[HEADER.FIELDS (SUBJECT)]"=>"Subject: test\r\n\r\n"}>]
        data = imap.uid_fetch(98, ["RFC822.SIZE", "INTERNALDATE"])[0]
        p data.seqno
        #=> 6
        p data.attr["RFC822.SIZE"]
        #=> 611
        p data.attr["INTERNALDATE"]
        #=> "12-Oct-2000 22:40:59 +0900"
        p data.attr["UID"]
        #=> 98

: store(set, attr, flags)
: uid_store(set, attr, flags)
      Sends a STORE command to alter data associated with a message
      in the mailbox. the set parameter is a number or an array of
      numbers or a Range object. the number is a message sequence
      number (store) or a unique identifier (uid_store).
      The return value is an array of ((<Net::IMAP::FetchData>)).

      ex).
        p imap.store(6..8, "+FLAGS", [:Deleted])
        #=> [#<Net::IMAP::FetchData seqno=6, attr={"FLAGS"=>[:Seen, :Deleted]}>, #<Net::IMAP::FetchData seqno=7, attr={"FLAGS"=>[:Seen, :Deleted]}>, #<Net::IMAP::FetchData seqno=8, attr={"FLAGS"=>[:Seen, :Deleted]}>]

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

== Net::IMAP::ContinuationRequest

Net::IMAP::ContinuationRequest represents command continuation requests.

The command continuation request response is indicated by a "+" token
instead of a tag.  This form of response indicates that the server is
ready to accept the continuation of a command from the client.  The
remainder of this response is a line of text.

  continue_req    ::= "+" SPACE (resp_text / base64)

=== Super Class

Struct

=== Methods

: data
      Returns the data (Net::IMAP::ResponseText).

: raw_data
      Returns the raw data string.

== Net::IMAP::UntaggedResponse

Net::IMAP::UntaggedResponse represents untagged responses.

Data transmitted by the server to the client and status responses
that do not indicate command completion are prefixed with the token
"*", and are called untagged responses.

  response_data   ::= "*" SPACE (resp_cond_state / resp_cond_bye /
                      mailbox_data / message_data / capability_data)

=== Super Class

Struct

=== Methods

: name
      Returns the name such as "FLAGS", "LIST", "FETCH"....

: data
      Returns the data such as an array of flag symbols,
      a ((<Net::IMAP::MailboxList>)) object....

: raw_data
      Returns the raw data string.

== Net::IMAP::TaggedResponse

Net::IMAP::TaggedResponse represents tagged responses.

The server completion result response indicates the success or
failure of the operation.  It is tagged with the same tag as the
client command which began the operation.

  response_tagged ::= tag SPACE resp_cond_state CRLF
  
  tag             ::= 1*<any ATOM_CHAR except "+">
  
  resp_cond_state ::= ("OK" / "NO" / "BAD") SPACE resp_text

=== Super Class

Struct

=== Methods

: tag
      Returns the tag.

: name
      Returns the name. the name is one of "OK", "NO", "BAD".

: data
      Returns the data. See ((<Net::IMAP::ResponseText>)).

: raw_data
      Returns the raw data string.

== Net::IMAP::ResponseText

Net::IMAP::ResponseText represents texts of responses.
The text may be prefixed by the response code.

  resp_text       ::= ["[" resp_text_code "]" SPACE] (text_mime2 / text)
                      ;; text SHOULD NOT begin with "[" or "="
  
=== Super Class

Struct

=== Methods

: code
      Returns the response code. See ((<Net::IMAP::ResponseCode>)).
      
: text
      Returns the text.

== Net::IMAP::ResponseCode

Net::IMAP::ResponseCode represents response codes.

  resp_text_code  ::= "ALERT" / "PARSE" /
                      "PERMANENTFLAGS" SPACE "(" #(flag / "\*") ")" /
                      "READ-ONLY" / "READ-WRITE" / "TRYCREATE" /
                      "UIDVALIDITY" SPACE nz_number /
                      "UNSEEN" SPACE nz_number /
                      atom [SPACE 1*<any TEXT_CHAR except "]">]

=== SuperClass

Struct

=== Methods

: name
      Returns the name such as "ALERT", "PERMANENTFLAGS", "UIDVALIDITY"....

: data
      Returns the data if it exists.

== Net::IMAP::MailboxList

Net::IMAP::MailboxList represents contents of the LIST response.

  mailbox_list    ::= "(" #("\Marked" / "\Noinferiors" /
                      "\Noselect" / "\Unmarked" / flag_extension) ")"
                      SPACE (<"> QUOTED_CHAR <"> / nil) SPACE mailbox

=== Super Class

Struct

=== Methods

: attr
      Returns the name attributes. Each name attribute is a symbol
      capitalized by String#capitalize, such as :Noselect (not :NoSelect).

: delim
      Returns the hierarchy delimiter

: name
      Returns the mailbox name.

== Net::IMAP::StatusData

Net::IMAP::StatusData represents contents of the STATUS response.

=== Super Class

Object

=== Methods

: mailbox
      Returns the mailbox name.

: attr
      Returns a hash. Each key is one of "MESSAGES", "RECENT", "UIDNEXT",
      "UIDVALIDITY", "UNSEEN". Each value is a number.

== Net::IMAP::FetchData

Net::IMAP::FetchData represents contents of the FETCH response.

=== Super Class

Object

=== Methods

: seqno
      Returns the message sequence number.
      (Note: not the unique identifier, even for the UID command response.)

: attr
      Returns a hash. Each key is a data item name, and each value is
      its value.

      The current data items are:

      : BODY
          A form of BODYSTRUCTURE without extension data.
      : BODY[<section>]<<origin_octet>>
          A string expressing the body contents of the specified section.
      : BODYSTRUCTURE
          An object that describes the ((<[MIME-IMB]>)) body structure of a message.
          See ((<Net::IMAP::BodyTypeBasic>)), ((<Net::IMAP::BodyTypeText>)),
          ((<Net::IMAP::BodyTypeMessage>)), ((<Net::IMAP::BodyTypeMultipart>)).
      : ENVELOPE
          A ((<Net::IMAP::Envelope>)) object that describes the envelope
          structure of a message.
      : FLAGS
          A array of flag symbols that are set for this message. flag symbols
          are capitalized by String#capitalize.
      : INTERNALDATE
          A string representing the internal date of the message.
      : RFC822
          Equivalent to BODY[].
      : RFC822.HEADER
          Equivalent to BODY.PEEK[HEADER].
      : RFC822.SIZE
          A number expressing the ((<[RFC-822]>)) size of the message.
      : RFC822.TEXT
          Equivalent to BODY[TEXT].
      : UID
          A number expressing the unique identifier of the message.

== Net::IMAP::Envelope

Net::IMAP::Envelope represents envelope structures of messages.

=== Super Class

Struct

=== Methods

: date
      Retunns a string that represents the date.

: subject
      Retunns a string that represents the subject.

: from
      Retunns an array of ((<Net::IMAP::Address>)) that represents the from.

: sender
      Retunns an array of ((<Net::IMAP::Address>)) that represents the sender.

: reply_to
      Retunns an array of ((<Net::IMAP::Address>)) that represents the reply-to.

: to
      Retunns an array of ((<Net::IMAP::Address>)) that represents the to.

: cc
      Retunns an array of ((<Net::IMAP::Address>)) that represents the cc.

: bcc
      Retunns an array of ((<Net::IMAP::Address>)) that represents the bcc.

: in_reply_to
      Retunns a string that represents the in-reply-to.

: message_id
      Retunns a string that represents the message-id.

== Net::IMAP::Address

((<Net::IMAP::Address>)) represents electronic mail addresses.

=== Super Class

Struct

=== Methods

: name
      Returns the phrase from ((<[RFC-822]>)) mailbox.

: route
      Returns the route from ((<[RFC-822]>)) route-addr.

: mailbox
      nil indicates end of ((<[RFC-822]>)) group.
      If non-nil and host is nil, returns ((<[RFC-822]>)) group name.
      Otherwise, returns ((<[RFC-822]>)) local-part

: host
      nil indicates ((<[RFC-822]>)) group syntax.
      Otherwise, returns ((<[RFC-822]>)) domain name.

== Net::IMAP::ContentDisposition

Net::IMAP::ContentDisposition represents Content-Disposition fields.

=== Super Class

Struct

=== Methods

: dsp_type
      Returns the disposition type.

: param
      Returns a hash that represents parameters of the Content-Disposition
      field.

== Net::IMAP::BodyTypeBasic

Net::IMAP::BodyTypeBasic represents basic body structures of messages.

=== Super Class

Struct

=== Methods

: media_type
      Returns the content media type name as defined in ((<[MIME-IMB]>)).

: subtype
      Returns the content subtype name as defined in ((<[MIME-IMB]>)).

: param
      Returns a hash that represents parameters as defined in
      ((<[MIME-IMB]>)).

: content_id
      Returns a string giving the content id as defined in ((<[MIME-IMB]>)).

: description
      Returns a string giving the content description as defined in
      ((<[MIME-IMB]>)).

: encoding
      Returns a string giving the content transfer encoding as defined in
      ((<[MIME-IMB]>)).

: size
      Returns a number giving the size of the body in octets.

: md5
      Returns a string giving the body MD5 value as defined in ((<[MD5]>)).

: disposition
      Returns a ((<Net::IMAP::ContentDisposition>)) object giving
      the content disposition.

: language
      Returns a string or an array of strings giving the body
      language value as defined in [LANGUAGE-TAGS].

: extension
      Returns extension data.

: multipart?
      Returns false.

== Net::IMAP::BodyTypeText

Net::IMAP::BodyTypeText represents TEXT body structures of messages.

=== Super Class

Struct

=== Methods

: lines
      Returns the size of the body in text lines.

And Net::IMAP::BodyTypeText has all methods of ((<Net::IMAP::BodyTypeBasic>)).

== Net::IMAP::BodyTypeMessage

Net::IMAP::BodyTypeMessage represents MESSAGE/RFC822 body structures of messages.

=== Super Class

Struct

=== Methods

: envelope
      Returns a ((<Net::IMAP::Envelope>)) giving the envelope structure.

: body
      Returns an object giving the body structure.

And Net::IMAP::BodyTypeMessage has all methods of ((<Net::IMAP::BodyTypeText>)).

== Net::IMAP::BodyTypeText

=== Super Class

Struct

=== Methods

: media_type
      Returns the content media type name as defined in ((<[MIME-IMB]>)).

: subtype
      Returns the content subtype name as defined in ((<[MIME-IMB]>)).

: parts
      Returns multiple parts.

: param
      Returns a hash that represents parameters as defined in
      ((<[MIME-IMB]>)).

: disposition
      Returns a ((<Net::IMAP::ContentDisposition>)) object giving
      the content disposition.

: language
      Returns a string or an array of strings giving the body
      language value as defined in [LANGUAGE-TAGS].

: extension
      Returns extension data.

: multipart?
      Returns true.

== References

: [IMAP]
    M. Crispin, "INTERNET MESSAGE ACCESS PROTOCOL - VERSION 4rev1",
    RFC 2060, December 1996.

: [LANGUAGE-TAGS]
    Alvestrand, H., "Tags for the Identification of
    Languages", RFC 1766, March 1995.

: [MD5]
    Myers, J., and M. Rose, "The Content-MD5 Header Field", RFC
    1864, October 1995.

: [MIME-IMB]
    Freed, N., and N. Borenstein, "MIME (Multipurpose Internet
    Mail Extensions) Part One: Format of Internet Message Bodies", RFC
    2045, November 1996.

: [RFC-822]
    Crocker, D., "Standard for the Format of ARPA Internet Text
    Messages", STD 11, RFC 822, University of Delaware, August 1982.

=end

require "socket"
require "digest/md5"

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
	if resp.instance_of?(ContinueRequest)
	  data = authenticator.process(resp.data.text.unpack("m")[0])
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
      return @responses.delete("STATUS")[-1][1]
    end

    def append(mailbox, message, flags = nil, date_time = nil)
      args = []
      if flags
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
      return @responses.delete("EXPUNGE")
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
      if /\ABYE\z/ni =~ @greeting.name
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
	  $stderr.printf("R: %s\n", resp.inspect)
	end
	case resp
	when TaggedResponse
	  case resp.name
	  when /\A(?:NO)\z/ni
	    raise NoResponseError, resp.data.text
	  when /\A(?:BAD)\z/ni
	    raise BadResponseError, resp.data.text
	  else
	    return resp
	  end
	when UntaggedResponse
	  if /\ABYE\z/ni =~ resp.name &&
	      cmd != "LOGOUT"
	    raise ByeResponseError, resp.data.text
	  end
	  record_response(resp.name, resp.data)
	  if resp.data.instance_of?(ResponseText) &&
	      (code = resp.data.code)
	    record_response(code.name, code.data)
	  end
	end
	block.call(resp) if block
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
      when /[\x80-\xff\r\n]/n
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
      if keys.instance_of?(String)
	keys = [RawData.new(keys)]
      else
	normalize_searching_criteria(keys)
      end
      if charset
	send_command(cmd, "CHARSET", charset, *keys)
      else
	send_command(cmd, *keys)
      end
      return @responses.delete("SEARCH")[-1]
    end

    def fetch_internal(cmd, set, attr)
      if attr.instance_of?(String)
	attr = RawData.new(attr)
      end
      @responses.delete("FETCH")
      send_command(cmd, MessageSet.new(set), attr)
      return @responses.delete("FETCH")
    end

    def store_internal(cmd, set, attr, flags)
      if attr.instance_of?(String)
	attr = RawData.new(attr)
      end
      @responses.delete("FETCH")
      send_command(cmd, MessageSet.new(set), attr, flags)
      return @responses.delete("FETCH")
    end

    def copy_internal(cmd, set, mailbox)
      send_command(cmd, MessageSet.new(set), mailbox)
    end

    def sort_internal(cmd, sort_keys, search_keys, charset)
      if search_keys.instance_of?(String)
	search_keys = [RawData.new(search_keys)]
      else
	normalize_searching_criteria(search_keys)
      end
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

    class RawData
      def format_data
	return @data
      end

      private

      def initialize(data)
	@data = data
      end
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

    ContinueRequest = Struct.new(:data, :raw_data)
    UntaggedResponse = Struct.new(:name, :data, :raw_data)
    TaggedResponse = Struct.new(:tag, :name, :data, :raw_data)
    ResponseText = Struct.new(:code, :text)
    ResponseCode = Struct.new(:name, :data)
    MailboxList = Struct.new(:attr, :delim, :name)
    StatusData = Struct.new(:mailbox, :attr)
    FetchData = Struct.new(:seqno, :attr)
    Envelope = Struct.new(:date, :subject, :from, :sender, :reply_to,
			  :to, :cc, :bcc, :in_reply_to, :message_id)
    Address = Struct.new(:name, :route, :mailbox, :host)
    ContentDisposition = Struct.new(:dsp_type, :param)

    class BodyTypeBasic < Struct.new(:media_type, :subtype,
				     :param, :content_id,
				     :description, :encoding, :size,
				     :md5, :disposition, :language,
				     :extension)
      def multipart?
	return false
      end

      def media_subtype
	$stderr.printf("warning: media_subtype is obsolete.\n")
	$stderr.printf("         use subtype instead.\n")
	return subtype
      end
    end

    class BodyTypeText < Struct.new(:media_type, :subtype,
				    :param, :content_id,
				    :description, :encoding, :size,
				    :lines,
				    :md5, :disposition, :language,
				    :extension)
      def multipart?
	return false
      end

      def media_subtype
	$stderr.printf("warning: media_subtype is obsolete.\n")
	$stderr.printf("         use subtype instead.\n")
	return subtype
      end
    end

    class BodyTypeMessage < Struct.new(:media_type, :subtype,
				       :param, :content_id,
				       :description, :encoding, :size,
				       :envelope, :body, :lines,
				       :md5, :disposition, :language,
				       :extension)
      def multipart?
	return false
      end

      def media_subtype
	$stderr.printf("warning: media_subtype is obsolete.\n")
	$stderr.printf("         use subtype instead.\n")
	return subtype
      end
    end

    class BodyTypeMultipart < Struct.new(:media_type, :subtype,
					 :parts,
					 :param, :disposition, :language,
					 :extension)
      def multipart?
	return true
      end

      def media_subtype
	$stderr.printf("warning: media_subtype is obsolete.\n")
	$stderr.printf("         use subtype instead.\n")
	return subtype
      end
    end

    class ResponseParser
      def parse(str)
	@str = str
	@pos = 0
	@lex_state = EXPR_BEG
	@token = nil
	return response
      end

      private

      EXPR_BEG		= :EXPR_BEG
      EXPR_DATA		= :EXPR_DATA
      EXPR_TEXT		= :EXPR_TEXT
      EXPR_RTEXT	= :EXPR_RTEXT
      EXPR_CTEXT	= :EXPR_CTEXT

      T_SPACE	= :SPACE
      T_NIL	= :NIL
      T_NUMBER	= :NUMBER
      T_ATOM	= :ATOM
      T_QUOTED	= :QUOTED
      T_LPAR	= :LPAR
      T_RPAR	= :RPAR
      T_BSLASH	= :BSLASH
      T_STAR	= :STAR
      T_LBRA	= :LBRA
      T_RBRA	= :RBRA
      T_LITERAL	= :LITERAL
      T_PLUS	= :PLUS
      T_PERCENT	= :PERCENT
      T_CRLF	= :CRLF
      T_EOF	= :EOF
      T_TEXT	= :TEXT

      BEG_REGEXP = /\G(?:\
(?# 1:	SPACE	)( )|\
(?# 2:	NIL	)(NIL)(?=[\x80-\xff(){ \x00-\x1f\x7f%*"\\\[\]+])|\
(?# 3:	NUMBER	)(\d+)(?=[\x80-\xff(){ \x00-\x1f\x7f%*"\\\[\]+])|\
(?# 4:	ATOM	)([^\x80-\xff(){ \x00-\x1f\x7f%*"\\\[\]+]+)|\
(?# 5:	QUOTED	)"((?:[^\x80-\xff\x00\r\n"\\]|\\["\\])*)"|\
(?# 6:	LPAR	)(\()|\
(?# 7:	RPAR	)(\))|\
(?# 8:	BSLASH	)(\\)|\
(?# 9:	STAR	)(\*)|\
(?# 10:	LBRA	)(\[)|\
(?# 11:	RBRA	)(\])|\
(?# 12:	LITERAL	)\{(\d+)\}\r\n|\
(?# 13:	PLUS	)(\+)|\
(?# 14:	PERCENT	)(%)|\
(?# 15:	CRLF	)(\r\n)|\
(?# 16:	EOF	)(\z))/ni

      DATA_REGEXP = /\G(?:\
(?# 1:	SPACE	)( )|\
(?# 2:	NIL	)(NIL)|\
(?# 3:	NUMBER	)(\d+)|\
(?# 4:	QUOTED	)"((?:[^\x80-\xff\x00\r\n"\\]|\\["\\])*)"|\
(?# 5:	LITERAL	)\{(\d+)\}\r\n|\
(?# 6:	LPAR	)(\()|\
(?# 7:	RPAR	)(\)))/ni

      TEXT_REGEXP = /\G(?:\
(?# 1:	TEXT	)([^\x00\x80-\xff\r\n]*))/ni

      RTEXT_REGEXP = /\G(?:\
(?# 1:	LBRA	)(\[)|\
(?# 2:	TEXT	)([^\x00\x80-\xff\r\n]*))/ni

      CTEXT_REGEXP = /\G(?:\
(?# 1:	TEXT	)([^\x00\x80-\xff\r\n\]]*))/ni

      Token = Struct.new(:symbol, :value)

      def response
	token = lookahead
	case token.symbol
	when T_PLUS
	  result = continue_req
	when T_STAR
	  result = response_untagged
	else
	  result = response_tagged
	end
	match(T_CRLF)
	match(T_EOF)
	return result
      end

      def continue_req
	match(T_PLUS)
	match(T_SPACE)
	return ContinueRequest.new(resp_text, @str)
      end

      def response_untagged
	match(T_STAR)
	match(T_SPACE)
	token = lookahead
	if token.symbol == T_NUMBER
	  return numeric_response
	elsif token.symbol == T_ATOM
	  case token.value
	  when /\A(?:OK|NO|BAD|BYE|PREAUTH)\z/ni
	    return response_cond
	  when /\A(?:FLAGS)\z/ni
	    return flags_response
	  when /\A(?:LIST|LSUB)\z/ni
	    return list_response
	  when /\A(?:SEARCH|SORT)\z/ni
	    return search_response
	  when /\A(?:STATUS)\z/ni
	    return status_response
	  when /\A(?:CAPABILITY)\z/ni
	    return capability_response
	  else
	    return text_response
	  end
	else
	  parse_error("unexpected token %s", token.symbol)
	end
      end

      def response_tagged
	tag = atom
	match(T_SPACE)
	token = match(T_ATOM)
	name = token.value.upcase
	match(T_SPACE)
	return TaggedResponse.new(tag, name, resp_text, @str)
      end

      def response_cond
	token = match(T_ATOM)
	name = token.value.upcase
	match(T_SPACE)
	return UntaggedResponse.new(name, resp_text, @str)
      end

      def numeric_response
	n = number
	match(T_SPACE)
	token = match(T_ATOM)
	name = token.value.upcase
	case name
	when "EXISTS", "RECENT", "EXPUNGE"
	  return UntaggedResponse.new(name, n, @str)
	when "FETCH"
	  shift_token
	  match(T_SPACE)
	  data = FetchData.new(n, msg_att)
	  return UntaggedResponse.new(name, data, @str)
	end
      end

      def msg_att
	match(T_LPAR)
	attr = {}
	while true
	  token = lookahead
	  case token.symbol
	  when T_RPAR
	    shift_token
	    break
	  when T_SPACE
	    shift_token
	    token = lookahead
	  end
	  case token.value
	  when /\A(?:ENVELOPE)\z/ni
	    name, val = envelope_data
	  when /\A(?:FLAGS)\z/ni
	    name, val = flags_data
	  when /\A(?:INTERNALDATE)\z/ni
	    name, val = internaldate_data
	  when /\A(?:RFC822(?:\.HEADER|\.TEXT)?)\z/ni
	    name, val = rfc822_text
	  when /\A(?:RFC822\.SIZE)\z/ni
	    name, val = rfc822_size
	  when /\A(?:BODY(?:STRUCTURE)?)\z/ni
	    name, val = body_data
	  when /\A(?:UID)\z/ni
	    name, val = uid_data
	  else
	    parse_error("unknown attribute `%s'", token.value)
	  end
	  attr[name] = val
	end
	return attr
      end

      def envelope_data
	token = match(T_ATOM)
	name = token.value.upcase
	match(T_SPACE)
	return name, envelope
      end

      def envelope
	@lex_state = EXPR_DATA
	match(T_LPAR)
	date = nstring
	match(T_SPACE)
	subject = nstring
	match(T_SPACE)
	from = address_list
	match(T_SPACE)
	sender = address_list
	match(T_SPACE)
	reply_to = address_list
	match(T_SPACE)
	to = address_list
	match(T_SPACE)
	cc = address_list
	match(T_SPACE)
	bcc = address_list
	match(T_SPACE)
	in_reply_to = nstring
	match(T_SPACE)
	message_id = nstring
	match(T_RPAR)
	@lex_state = EXPR_BEG
	return Envelope.new(date, subject, from, sender, reply_to,
			    to, cc, bcc, in_reply_to, message_id)
      end

      def flags_data
	token = match(T_ATOM)
	name = token.value.upcase
	match(T_SPACE)
	return name, flag_list
      end

      def internaldate_data
	token = match(T_ATOM)
	name = token.value.upcase
	match(T_SPACE)
	token = match(T_QUOTED)
	return name, token.value
      end

      def rfc822_text
	token = match(T_ATOM)
	name = token.value.upcase
	match(T_SPACE)
	return name, nstring
      end

      def rfc822_size
	token = match(T_ATOM)
	name = token.value.upcase
	match(T_SPACE)
	return name, number
      end

      def body_data
	token = match(T_ATOM)
	name = token.value.upcase
	token = lookahead
	if token.symbol == T_SPACE
	  shift_token
	  return name, body
	end
	name.concat(section)
	token = lookahead
	if token.symbol == T_ATOM
	  name.concat(token.value)
	  shift_token
	end
	match(T_SPACE)
	data = nstring
	return name, data
      end

      def body
	@lex_state = EXPR_DATA
	match(T_LPAR)
	token = lookahead
	if token.symbol == T_LPAR
	  result = body_type_mpart
	else
	  result = body_type_1part
	end
	match(T_RPAR)
	@lex_state = EXPR_BEG
	return result
      end

      def body_type_1part
	token = lookahead
	case token.value
	when /\A(?:TEXT)\z/ni
	  return body_type_text
	when /\A(?:MESSAGE)\z/ni
	  return body_type_msg
	else
	  return body_type_basic
	end
      end

      def body_type_basic
	mtype, msubtype = media_type
	match(T_SPACE)
	param, content_id, desc, enc, size = body_fields
	md5, disposition, language, extension = body_ext_1part
	return BodyTypeBasic.new(mtype, msubtype,
				 param, content_id,
				 desc, enc, size,
				 md5, disposition, language, extension)
      end

      def body_type_text
	mtype, msubtype = media_type
	match(T_SPACE)
	param, content_id, desc, enc, size = body_fields
	match(T_SPACE)
	lines = number
	md5, disposition, language, extension = body_ext_1part
	return BodyTypeText.new(mtype, msubtype,
				param, content_id,
				desc, enc, size,
				lines,
				md5, disposition, language, extension)
      end

      def body_type_msg
	mtype, msubtype = media_type
	match(T_SPACE)
	param, content_id, desc, enc, size = body_fields
	match(T_SPACE)
	env = envelope
	match(T_SPACE)
	b = body
	match(T_SPACE)
	lines = number
	md5, disposition, language, extension = body_ext_1part
	return BodyTypeMessage.new(mtype, msubtype,
				   param, content_id,
				   desc, enc, size,
				   env, b, lines,
				   md5, disposition, language, extension)
      end

      def body_type_mpart
	parts = []
	while true
	  token = lookahead
	  if token.symbol == T_SPACE
	    shift_token
	    break
	  end
	  parts.push(body)
	end
	mtype = "MULTIPART"
	msubtype = string.upcase
	param, disposition, language, extension = body_ext_mpart
	return BodyTypeMultipart.new(mtype, msubtype, parts,
				     param, disposition, language,
				     extension)
      end

      def media_type
	mtype = string.upcase
	match(T_SPACE)
	msubtype = string.upcase
	return mtype, msubtype
      end

      def body_fields
	param = body_fld_param
	match(T_SPACE)
	content_id = nstring
	match(T_SPACE)
	desc = nstring
	match(T_SPACE)
	enc = string.upcase
	match(T_SPACE)
	size = number
	return param, content_id, desc, enc, size
      end

      def body_fld_param
	token = lookahead
	if token.symbol == T_NIL
	  shift_token
	  return nil
	end
	match(T_LPAR)
	param = {}
	while true
	  token = lookahead
	  case token.symbol
	  when T_RPAR
	    shift_token
	    break
	  when T_SPACE
	    shift_token
	  end
	  name = string.upcase
	  match(T_SPACE)
	  val = string
	  param[name] = val
	end
	return param
      end

      def body_ext_1part
	token = lookahead
	if token.symbol == T_SPACE
	  shift_token
	else
	  return nil
	end
	md5 = nstring

	token = lookahead
	if token.symbol == T_SPACE
	  shift_token
	else
	  return md5
	end
	disposition = body_fld_dsp

	token = lookahead
	if token.symbol == T_SPACE
	  shift_token
	else
	  return md5, disposition
	end
	language = body_fld_lang

	token = lookahead
	if token.symbol == T_SPACE
	  shift_token
	else
	  return md5, disposition, language
	end

	extension = body_extensions
	return md5, disposition, language, extension
      end

      def body_ext_mpart
	token = lookahead
	if token.symbol == T_SPACE
	  shift_token
	else
	  return nil
	end
	param = body_fld_param

	token = lookahead
	if token.symbol == T_SPACE
	  shift_token
	else
	  return param
	end
	disposition = body_fld_dsp
	match(T_SPACE)
	language = body_fld_lang

	token = lookahead
	if token.symbol == T_SPACE
	  shift_token
	else
	  return param, disposition, language
	end

	extension = body_extensions
	return param, disposition, language, extension
      end

      def body_fld_dsp
	token = lookahead
	if token.symbol == T_NIL
	  shift_token
	  return nil
	end
	match(T_LPAR)
	dsp_type = string.upcase
	match(T_SPACE)
	param = body_fld_param
	match(T_RPAR)
	return ContentDisposition.new(dsp_type, param)
      end

      def body_fld_lang
	token = lookahead
	if token.symbol == T_LPAR
	  shift_token
	  result = []
	  while true
	    token = lookahead
	    case token.symbol
	    when T_RPAR
	      shift_token
	      return result
	    when T_SPACE
	      shift_token
	    end
	    result.push(string.upcase)
	  end
	else
	  lang = nstring
	  if lang
	    return lang.upcase
	  else
	    return lang
	  end
	end
      end

      def body_extensions
	result = []
	while true
	  token = lookahead
	  case token.symbol
	  when T_RPAR
	    return result
	  when T_SPACE
	    shift_token
	  end
	  result.push(body_extension)
	end
      end

      def body_extension
	token = lookahead
	case token.symbol
	when T_LPAR
	  shift_token
	  result = body_extensions
	  match(T_RPAR)
	  return result
	when T_NUMBER
	  return number
	else
	  return nstring
	end
      end

      def section
	str = ""
	token = match(T_LBRA)
	str.concat(token.value)
	token = match(T_ATOM, T_NUMBER, T_RBRA)
	if token.symbol == T_RBRA
	  str.concat(token.value)
	  return str
	end
	str.concat(token.value)
	token = lookahead
	if token.symbol == T_SPACE
	  shift_token
	  str.concat(token.value)
	  token = match(T_LPAR)
	  str.concat(token.value)
	  while true
	    token = lookahead
	    case token.symbol
	    when T_RPAR
	      str.concat(token.value)
	      shift_token
	      break
	    when T_SPACE
	      shift_token
	      str.concat(token.value)
	    end
	    str.concat(format_string(astring))
	  end
	end
	token = match(T_RBRA)
	str.concat(token.value)
	return str
      end

      def format_string(str)
	case str
	when ""
	  return '""'
	when /[\x80-\xff\r\n]/n
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

      def uid_data
	token = match(T_ATOM)
	name = token.value.upcase
	match(T_SPACE)
	return name, number
      end

      def text_response
	token = match(T_ATOM)
	name = token.value.upcase
	match(T_SPACE)
	@lex_state = EXPR_TEXT
	token = match(T_TEXT)
	@lex_state = EXPR_BEG
	return UntaggedResponse.new(name, token.value)
      end

      def flags_response
	token = match(T_ATOM)
	name = token.value.upcase
	match(T_SPACE)
	return UntaggedResponse.new(name, flag_list, @str)
      end

      def list_response
	token = match(T_ATOM)
	name = token.value.upcase
	match(T_SPACE)
	return UntaggedResponse.new(name, mailbox_list, @str)
      end

      def mailbox_list
	attr = flag_list
	match(T_SPACE)
	token = match(T_QUOTED, T_NIL)
	if token.symbol == T_NIL
	  delim = nil
	else
	  delim = token.value
	end
	match(T_SPACE)
	name = astring
	return MailboxList.new(attr, delim, name)
      end

      def search_response
	token = match(T_ATOM)
	name = token.value.upcase
	token = lookahead
	if token.symbol == T_SPACE
	  shift_token
	  data = []
	  while true
	    token = lookahead
	    case token.symbol
	    when T_CRLF
	      break
	    when T_SPACE
	      shift_token
	    end
	    data.push(number)
	  end
	else
	  data = []
	end
	return UntaggedResponse.new(name, data, @str)
      end

      def status_response
	token = match(T_ATOM)
	name = token.value.upcase
	match(T_SPACE)
	mailbox = astring
	match(T_SPACE)
	match(T_LPAR)
	attr = {}
	while true
	  token = lookahead
	  case token.symbol
	  when T_RPAR
	    shift_token
	    break
	  when T_SPACE
	    shift_token
	  end
	  token = match(T_ATOM)
	  key = token.value.upcase
	  match(T_SPACE)
	  val = number
	  attr[key] = val
	end
	data = StatusData.new(mailbox, attr)
	return UntaggedResponse.new(name, data, @str)
      end

      def capability_response
	token = match(T_ATOM)
	name = token.value.upcase
	match(T_SPACE)
	data = []
	while true
	  token = lookahead
	  case token.symbol
	  when T_CRLF
	    break
	  when T_SPACE
	    shift_token
	  end
	  data.push(atom.upcase)
	end
	return UntaggedResponse.new(name, data, @str)
      end

      def resp_text
	@lex_state = EXPR_RTEXT
	token = lookahead
	if token.symbol == T_LBRA
	  code = resp_text_code
	else
	  code = nil
	end
	token = match(T_TEXT)
	@lex_state = EXPR_BEG
	return ResponseText.new(code, token.value)
      end

      def resp_text_code
	@lex_state = EXPR_BEG
	match(T_LBRA)
	token = match(T_ATOM)
	name = token.value.upcase
	case name
	when /\A(?:ALERT|PARSE|READ-ONLY|READ-WRITE|TRYCREATE)\z/n
	  result = ResponseCode.new(name, nil)
	when /\A(?:PERMANENTFLAGS)\z/n
	  match(T_SPACE)
	  result = ResponseCode.new(name, flag_list)
	when /\A(?:UIDVALIDITY|UIDNEXT|UNSEEN)\z/n
	  match(T_SPACE)
	  result = ResponseCode.new(name, number)
	else
	  match(T_SPACE)
	  @lex_state = EXPR_CTEXT
	  token = match(T_TEXT)
	  @lex_state = EXPR_BEG
	  result = ResponseCode.new(name, token.value)
	end
	match(T_RBRA)
	@lex_state = EXPR_RTEXT
	return result
      end

      def address_list
	token = lookahead
	if token.symbol == T_NIL
	  shift_token
	  return nil
	else
	  result = []
	  match(T_LPAR)
	  while true
	    token = lookahead
	    case token.symbol
	    when T_RPAR
	      shift_token
	      break
	    when T_SPACE
	      shift_token
	    end
	    result.push(address)
	  end
	  return result
	end
      end

      ADDRESS_REGEXP = /\G\
(?# 1: NAME	)(?:NIL|"((?:[^\x80-\xff\x00\r\n"\\]|\\["\\])*)") \
(?# 2: ROUTE	)(?:NIL|"((?:[^\x80-\xff\x00\r\n"\\]|\\["\\])*)") \
(?# 3: MAILBOX	)(?:NIL|"((?:[^\x80-\xff\x00\r\n"\\]|\\["\\])*)") \
(?# 4: HOST	)(?:NIL|"((?:[^\x80-\xff\x00\r\n"\\]|\\["\\])*)")\
\)/ni

      def address
	match(T_LPAR)
	if @str.index(ADDRESS_REGEXP, @pos)
	  # address does not include literal.
	  @pos = $~.end(0)
	  name = $1
	  route = $2
	  mailbox = $3
	  host = $4
	  for s in [name, route, mailbox, host]
	    if s
	      s.gsub!(/\\(["\\])/n, "\\1")
	    end
	  end
	else
	  name = nstring
	  match(T_SPACE)
	  route = nstring
	  match(T_SPACE)
	  mailbox = nstring
	  match(T_SPACE)
	  host = nstring
	  match(T_RPAR)
	end
	return Address.new(name, route, mailbox, host)
      end

#        def flag_list
#  	result = []
#  	match(T_LPAR)
#  	while true
#  	  token = lookahead
#  	  case token.symbol
#  	  when T_RPAR
#  	    shift_token
#  	    break
#  	  when T_SPACE
#  	    shift_token
#  	  end
#  	  result.push(flag)
#  	end
#  	return result
#        end

#        def flag
#  	token = lookahead
#  	if token.symbol == T_BSLASH
#  	  shift_token
#  	  token = lookahead
#  	  if token.symbol == T_STAR
#  	    shift_token
#  	    return token.value.intern
#  	  else
#  	    return atom.intern
#  	  end
#  	else
#  	  return atom
#  	end
#        end

      FLAG_REGEXP = /\
(?# FLAG	)\\([^\x80-\xff(){ \x00-\x1f\x7f%"\\]+)|\
(?# ATOM	)([^\x80-\xff(){ \x00-\x1f\x7f%*"\\]+)/n

      def flag_list
	if @str.index(/\(([^)]*)\)/ni, @pos)
	  @pos = $~.end(0)
	  return $1.scan(FLAG_REGEXP).collect { |flag, atom|
	    atom || flag.capitalize.intern
	  }
	else
	  parse_error("invalid flag list")
	end
      end

      def nstring
	token = lookahead
	if token.symbol == T_NIL
	  shift_token
	  return nil
	else
	  return string
	end
      end

      def astring
	token = lookahead
	if string_token?(token)
	  return string
	else
	  return atom
	end
      end

      def string
	token = match(T_QUOTED, T_LITERAL)
	return token.value
      end

      STRING_TOKENS = [T_QUOTED, T_LITERAL]

      def string_token?(token)
	return STRING_TOKENS.include?(token.symbol)
      end

      def atom
  	result = ""
  	while true
  	  token = lookahead
  	  if atom_token?(token)
  	    result.concat(token.value)
  	    shift_token
  	  else
  	    if result.empty?
  	      parse_error("unexpected token %s", token.symbol)
  	    else
  	      return result
  	    end
  	  end
  	end
      end

      ATOM_TOKENS = [
	T_ATOM,
	T_NUMBER,
	T_NIL,
	T_LBRA,
	T_RBRA,
	T_PLUS
      ]

      def atom_token?(token)
	return ATOM_TOKENS.include?(token.symbol)
      end

      def number
	token = match(T_NUMBER)
	return token.value.to_i
      end

      def nil_atom
	match(T_NIL)
	return nil
      end

      def match(*args)
	token = lookahead
	unless args.include?(token.symbol)
	  parse_error('unexpected token %s (expected %s)',
		      token.symbol.id2name,
		      args.collect {|i| i.id2name}.join(" or "))
	end
	shift_token
	return token
      end

      def lookahead
	unless @token
	  @token = next_token
	end
	return @token
      end

      def shift_token
	@token = nil
      end

      def next_token
	case @lex_state
	when EXPR_BEG
	  if @str.index(BEG_REGEXP, @pos)
	    @pos = $~.end(0)
	    if $1
	      return Token.new(T_SPACE, $+)
	    elsif $2
	      return Token.new(T_NIL, $+)
	    elsif $3
	      return Token.new(T_NUMBER, $+)
	    elsif $4
	      return Token.new(T_ATOM, $+)
	    elsif $5
	      return Token.new(T_QUOTED,
			       $+.gsub(/\\(["\\])/n, "\\1"))
	    elsif $6
	      return Token.new(T_LPAR, $+)
	    elsif $7
	      return Token.new(T_RPAR, $+)
	    elsif $8
	      return Token.new(T_BSLASH, $+)
	    elsif $9
	      return Token.new(T_STAR, $+)
	    elsif $10
	      return Token.new(T_LBRA, $+)
	    elsif $11
	      return Token.new(T_RBRA, $+)
	    elsif $12
	      len = $+.to_i
	      val = @str[@pos, len]
	      @pos += len
	      return Token.new(T_LITERAL, val)
	    elsif $13
	      return Token.new(T_PLUS, $+)
	    elsif $14
	      return Token.new(T_PERCENT, $+)
	    elsif $15
	      return Token.new(T_CRLF, $+)
	    elsif $16
	      return Token.new(T_EOF, $+)
	    else
	      parse_error("[Net::IMAP BUG] BEG_REGEXP is invalid")
	    end
	  else
	    @str.index(/\S*/n, @pos)
	    parse_error("unknown token - %s", $&.dump)
	  end
	when EXPR_DATA
	  if @str.index(DATA_REGEXP, @pos)
	    @pos = $~.end(0)
	    if $1
	      return Token.new(T_SPACE, $+)
	    elsif $2
	      return Token.new(T_NIL, $+)
	    elsif $3
	      return Token.new(T_NUMBER, $+)
	    elsif $4
	      return Token.new(T_QUOTED,
			       $+.gsub(/\\(["\\])/n, "\\1"))
	    elsif $5
	      len = $+.to_i
	      val = @str[@pos, len]
	      @pos += len
	      return Token.new(T_LITERAL, val)
	    elsif $6
	      return Token.new(T_LPAR, $+)
	    elsif $7
	      return Token.new(T_RPAR, $+)
	    else
	      parse_error("[Net::IMAP BUG] BEG_REGEXP is invalid")
	    end
	  else
	    @str.index(/\S*/n, @pos)
	    parse_error("unknown token - %s", $&.dump)
	  end
	when EXPR_TEXT
	  if @str.index(TEXT_REGEXP, @pos)
	    @pos = $~.end(0)
	    if $1
	      return Token.new(T_TEXT, $+)
	    else
	      parse_error("[Net::IMAP BUG] TEXT_REGEXP is invalid")
	    end
	  else
	    @str.index(/\S*/n, @pos)
	    parse_error("unknown token - %s", $&.dump)
	  end
	when EXPR_RTEXT
	  if @str.index(RTEXT_REGEXP, @pos)
	    @pos = $~.end(0)
	    if $1
	      return Token.new(T_LBRA, $+)
	    elsif $2
	      return Token.new(T_TEXT, $+)
	    else
	      parse_error("[Net::IMAP BUG] RTEXT_REGEXP is invalid")
	    end
	  else
	    @str.index(/\S*/n, @pos)
	    parse_error("unknown token - %s", $&.dump)
	  end
	when EXPR_CTEXT
	  if @str.index(CTEXT_REGEXP, @pos)
	    @pos = $~.end(0)
	    if $1
	      return Token.new(T_TEXT, $+)
	    else
	      parse_error("[Net::IMAP BUG] CTEXT_REGEXP is invalid")
	    end
	  else
	    @str.index(/\S*/n, @pos) #/
	    parse_error("unknown token - %s", $&.dump)
	  end
	else
	  parse_error("illegal @lex_state - %s", @lex_state.inspect)
	end
      end

      def parse_error(fmt, *args)
	if IMAP.debug
	  $stderr.printf("@str: %s\n", @str.dump)
	  $stderr.printf("@pos: %d\n", @pos)
	  $stderr.printf("@lex_state: %s\n", @lex_state)
	  if @token.symbol
	    $stderr.printf("@token.symbol: %s\n", @token.symbol)
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
	  key = Digest::MD5.digest(key)
	end

	k_ipad = key + "\0" * (64 - key.length)
	k_opad = key + "\0" * (64 - key.length)
	for i in 0..63
	  k_ipad[i] ^= 0x36
	  k_opad[i] ^= 0x5c
	end

	digest = Digest::MD5.digest(k_ipad + text)

	return Digest::MD5.hexdigest(k_opad + digest)
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
