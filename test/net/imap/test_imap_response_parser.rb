require "net/imap"
require "test/unit"

class IMAPResponseParserTest < Test::Unit::TestCase
  def setup
    @do_not_reverse_lookup = Socket.do_not_reverse_lookup
    Socket.do_not_reverse_lookup = true
    if Net::IMAP.respond_to?(:max_flag_count)
      @max_flag_count = Net::IMAP.max_flag_count
      Net::IMAP.max_flag_count = 3
    end
  end

  def teardown
    Socket.do_not_reverse_lookup = @do_not_reverse_lookup
    if Net::IMAP.respond_to?(:max_flag_count)
      Net::IMAP.max_flag_count = @max_flag_count
    end
  end

  def test_flag_list_safe
    parser = Net::IMAP::ResponseParser.new
    response = lambda {
      $SAFE = 1
      parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* LIST (\\HasChildren) "." "INBOX"
EOF
    }.call
    assert_equal [:Haschildren], response.data.attr
  end

  def test_flag_list_too_many_flags
    parser = Net::IMAP::ResponseParser.new
    assert_nothing_raised do
      3.times do |i|
      parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* LIST (\\Foo#{i}) "." "INBOX"
EOF
      end
    end
    assert_raise(Net::IMAP::FlagCountError) do
      parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* LIST (\\Foo3) "." "INBOX"
EOF
    end
  end

  def test_flag_list_many_same_flags
    parser = Net::IMAP::ResponseParser.new
    assert_nothing_raised do
      100.times do
      parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* LIST (\\Foo) "." "INBOX"
EOF
      end
    end
  end

  def test_flag_xlist_inbox
    parser = Net::IMAP::ResponseParser.new
	response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* XLIST (\\Inbox) "." "INBOX"
EOF
    assert_equal [:Inbox], response.data.attr
  end

  def test_resp_text_code
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* OK [CLOSED] Previous mailbox closed.
EOF
    assert_equal "CLOSED", response.data.code.name
  end

  def test_search_response
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* SEARCH
EOF
    assert_equal [], response.data
    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* SEARCH 1
EOF
    assert_equal [1], response.data
    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* SEARCH 1 2 3
EOF
    assert_equal [1, 2, 3], response.data
  end

  def test_search_response_of_yahoo
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* SEARCH 1\s
EOF
    assert_equal [1], response.data
    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* SEARCH 1 2 3\s
EOF
    assert_equal [1, 2, 3], response.data
  end

  def test_msg_att_extra_space
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* 1 FETCH (UID 92285)
EOF
    assert_equal 92285, response.data.attr["UID"]

    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* 1 FETCH (UID 92285 )
EOF
    assert_equal 92285, response.data.attr["UID"]

    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* 1 FETCH (UID 92285  )
EOF
  end

  def test_msg_att_parse_error
    parser = Net::IMAP::ResponseParser.new
    e = assert_raise(Net::IMAP::ResponseParseError) {
      response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* 123 FETCH (UNKNOWN 92285)
EOF
    }
    assert_match(/ for \{123\}/, e.message)
  end

  def test_msg_att_rfc822_text
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* 123 FETCH (RFC822 {5}
foo
)
EOF
    assert_equal("foo\r\n", response.data.attr["RFC822"])
    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* 123 FETCH (RFC822[] {5}
foo
)
EOF
    assert_equal("foo\r\n", response.data.attr["RFC822"])
  end

  # [Bug #6397] [ruby-core:44849]
  def test_body_type_attachment
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* 980 FETCH (UID 2862 BODYSTRUCTURE ((("TEXT" "PLAIN" ("CHARSET" "iso-8859-1") NIL NIL "7BIT" 416 21 NIL NIL NIL)("TEXT" "HTML" ("CHARSET" "iso-8859-1") NIL NIL "7BIT" 1493 32 NIL NIL NIL) "ALTERNATIVE" ("BOUNDARY" "Boundary_(ID_IaecgfnXwG5bn3x8lIeGIQ)") NIL NIL)("MESSAGE" "RFC822" ("NAME" "Fw_ ____ _____ ____.eml") NIL NIL "7BIT" 1980088 NIL ("ATTACHMENT" ("FILENAME" "Fw_ ____ _____ ____.eml")) NIL) "MIXED" ("BOUNDARY" "Boundary_(ID_eDdLc/j0mBIzIlR191pHjA)") NIL NIL))
EOF
    assert_equal("Fw_ ____ _____ ____.eml",
      response.data.attr["BODYSTRUCTURE"].parts[1].body.param["FILENAME"])
  end

  def assert_parseable(s)
    parser = Net::IMAP::ResponseParser.new
    parser.parse(s.gsub(/\n/, "\r\n").taint)
  end

  # [Bug #7146]
  def test_msg_delivery_status
    # This was part of a larger response that caused crashes, but this was the
    # minimal test case to demonstrate it
    assert_parseable <<EOF
* 4902 FETCH (BODY (("MESSAGE" "DELIVERY-STATUS" NIL NIL NIL "7BIT" 324) "REPORT"))
EOF
  end

  # [Bug #7147]
  def test_msg_with_message_rfc822_attachment
    assert_parseable <<EOF
* 5441 FETCH (BODY ((("TEXT" "PLAIN" ("CHARSET" "iso-8859-1") NIL NIL "QUOTED-PRINTABLE" 69 1)("TEXT" "HTML" ("CHARSET" "iso-8859-1") NIL NIL "QUOTED-PRINTABLE" 455 12) "ALTERNATIVE")("MESSAGE" "RFC822" ("NAME" "ATT00026.eml") NIL NIL "7BIT" 4079755) "MIXED"))
EOF
  end

  # [Bug #7153]
  def test_msg_body_mixed
    assert_parseable <<EOF
* 1038 FETCH (BODY ("MIXED"))
EOF
  end

  # [Bug #8281]
  def test_acl
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* ACL "INBOX/share" "imshare2copy1366146467@xxxxxxxxxxxxxxxxxx.com" lrswickxteda
EOF
    assert_equal("ACL", response.name)
    assert_equal(1, response.data.length)
    assert_equal("INBOX/share", response.data[0].mailbox)
    assert_equal("imshare2copy1366146467@xxxxxxxxxxxxxxxxxx.com",
                 response.data[0].user)
    assert_equal("lrswickxteda", response.data[0].rights)
  end

  # [Bug #8415]
  def test_capability
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse("* CAPABILITY st11p00mm-iscream009 1Q49 XAPPLEPUSHSERVICE IMAP4 IMAP4rev1 SASL-IR AUTH=ATOKEN AUTH=PLAIN\r\n")
    assert_equal("CAPABILITY", response.name)
    assert_equal("AUTH=PLAIN", response.data.last)
    response = parser.parse("* CAPABILITY st11p00mm-iscream009 1Q49 XAPPLEPUSHSERVICE IMAP4 IMAP4rev1 SASL-IR AUTH=ATOKEN AUTH=PLAIN \r\n")
    assert_equal("CAPABILITY", response.name)
    assert_equal("AUTH=PLAIN", response.data.last)
  end
end
