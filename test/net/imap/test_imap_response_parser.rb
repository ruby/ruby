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
* SEARCH 1 
EOF
    assert_equal [1], response.data
    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* SEARCH 1 2 3 
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

  def assert_parseable(s)
    parser = Net::IMAP::ResponseParser.new
    parser.parse(s.gsub(/\n/, "\r\n").taint)
  end

  def test_msg_delivery_status
    # This was part of a larger response that caused crashes, but this was the
    # minimal test case to demonstrate it
    assert_parseable <<EOF
* 4902 FETCH (BODY (("MESSAGE" "DELIVERY-STATUS" NIL NIL NIL "7BIT" 324) "REPORT"))
EOF
  end

  def test_msg_with_message_rfc822_attachment
    assert_parseable <<EOF
* 5441 FETCH (BODY ((("TEXT" "PLAIN" ("CHARSET" "iso-8859-1") NIL NIL "QUOTED-PRINTABLE" 69 1)("TEXT" "HTML" ("CHARSET" "iso-8859-1") NIL NIL "QUOTED-PRINTABLE" 455 12) "ALTERNATIVE")("MESSAGE" "RFC822" ("NAME" "ATT00026.eml") NIL NIL "7BIT" 4079755) "MIXED"))
EOF
  end
end
