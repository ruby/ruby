# frozen_string_literal: true

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
  end

  def test_msg_att_parse_error
    parser = Net::IMAP::ResponseParser.new
    e = assert_raise(Net::IMAP::ResponseParseError) {
      parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
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

  # [Bug #8167]
  def test_msg_delivery_status_with_extra_data
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse(<<EOF.gsub(/\n/, "\r\n").taint)
* 29021 FETCH (RFC822.SIZE 3162 UID 113622 RFC822.HEADER {1155}
Return-path: <>
Envelope-to: info@xxxxxxxx.si
Delivery-date: Tue, 26 Mar 2013 12:42:58 +0100
Received: from mail by xxxx.xxxxxxxxxxx.net with spam-scanned (Exim 4.76)
	id 1UKSHI-000Cwl-AR
	for info@xxxxxxxx.si; Tue, 26 Mar 2013 12:42:58 +0100
X-Spam-Checker-Version: SpamAssassin 3.3.1 (2010-03-16) on xxxx.xxxxxxxxxxx.net
X-Spam-Level: **
X-Spam-Status: No, score=2.1 required=7.0 tests=DKIM_ADSP_NXDOMAIN,RDNS_NONE
	autolearn=no version=3.3.1
Received: from [xx.xxx.xxx.xx] (port=56890 helo=xxxxxx.localdomain)
	by xxxx.xxxxxxxxxxx.net with esmtp (Exim 4.76)
	id 1UKSHI-000Cwi-9j
	for info@xxxxxxxx.si; Tue, 26 Mar 2013 12:42:56 +0100
Received: by xxxxxx.localdomain (Postfix)
	id 72725BEA64A; Tue, 26 Mar 2013 12:42:55 +0100 (CET)
Date: Tue, 26 Mar 2013 12:42:55 +0100 (CET)
From: MAILER-DAEMON@xxxxxx.localdomain (Mail Delivery System)
Subject: Undelivered Mail Returned to Sender
To: info@xxxxxxxx.si
Auto-Submitted: auto-replied
MIME-Version: 1.0
Content-Type: multipart/report; report-type=delivery-status;
	boundary="27797BEA649.1364298175/xxxxxx.localdomain"
Message-Id: <20130326114255.72725BEA64A@xxxxxx.localdomain>

 BODYSTRUCTURE (("text" "plain" ("charset" "us-ascii") NIL "Notification" "7bit" 510 14 NIL NIL NIL NIL)("message" "delivery-status" NIL NIL "Delivery report" "7bit" 410 NIL NIL NIL NIL)("text" "rfc822-headers" ("charset" "us-ascii") NIL "Undelivered Message Headers" "7bit" 612 15 NIL NIL NIL NIL) "report" ("report-type" "delivery-status" "boundary" "27797BEA649.1364298175/xxxxxx.localdomain") NIL NIL NIL))
EOF
    delivery_status = response.data.attr["BODYSTRUCTURE"].parts[1]
    assert_equal("MESSAGE", delivery_status.media_type)
    assert_equal("DELIVERY-STATUS", delivery_status.subtype)
    assert_equal(nil, delivery_status.param)
    assert_equal(nil, delivery_status.content_id)
    assert_equal("Delivery report", delivery_status.description)
    assert_equal("7BIT", delivery_status.encoding)
    assert_equal(410, delivery_status.size)
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

  def test_mixed_boundary
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse("* 2688 FETCH (UID 179161 BODYSTRUCTURE (" \
                            "(\"TEXT\" \"PLAIN\" (\"CHARSET\" \"iso-8859-1\") NIL NIL \"QUOTED-PRINTABLE\" 200 4 NIL NIL NIL)" \
                            "(\"MESSAGE\" \"DELIVERY-STATUS\" NIL NIL NIL \"7BIT\" 318 NIL NIL NIL)" \
                            "(\"MESSAGE\" \"RFC822\" NIL NIL NIL \"7BIT\" 2177" \
                            " (\"Tue, 11 May 2010 18:28:16 -0400\" \"Re: Welcome letter\" (" \
                              "(\"David\" NIL \"info\" \"xxxxxxxx.si\")) " \
                              "((\"David\" NIL \"info\" \"xxxxxxxx.si\")) " \
                              "((\"David\" NIL \"info\" \"xxxxxxxx.si\")) " \
                              "((\"Doretha\" NIL \"doretha.info\" \"xxxxxxxx.si\")) " \
                              "NIL NIL " \
                              "\"<AC1D15E06EA82F47BDE18E851CC32F330717704E@localdomain>\" " \
                              "\"<AANLkTikKMev1I73L2E7XLjRs67IHrEkb23f7ZPmD4S_9@localdomain>\")" \
                            " (\"MIXED\" (\"BOUNDARY\" \"000e0cd29212e3e06a0486590ae2\") NIL NIL)" \
                            " 37 NIL NIL NIL)" \
                            " \"REPORT\" (\"BOUNDARY\" \"16DuG.4XbaNOvCi.9ggvq.8Ipnyp3\" \"REPORT-TYPE\" \"delivery-status\") NIL NIL))\r\n")
    empty_part = response.data.attr['BODYSTRUCTURE'].parts[2]
    assert_equal(empty_part.lines, 37)
    assert_equal(empty_part.body.media_type, 'MULTIPART')
    assert_equal(empty_part.body.subtype, 'MIXED')
    assert_equal(empty_part.body.param['BOUNDARY'], '000e0cd29212e3e06a0486590ae2')
  end

  # [Bug #10112]
  def test_search_modseq
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse("* SEARCH 87216 87221 (MODSEQ 7667567)\r\n")
    assert_equal("SEARCH", response.name)
    assert_equal([87216, 87221], response.data)
  end

  # [Bug #11128]
  def test_body_ext_mpart_without_lang
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse("* 4 FETCH (BODY (((\"text\" \"plain\" (\"charset\" \"utf-8\") NIL NIL \"7bit\" 257 9 NIL NIL NIL NIL)(\"text\" \"html\" (\"charset\" \"utf-8\") NIL NIL \"quoted-printable\" 655 9 NIL NIL NIL NIL) \"alternative\" (\"boundary\" \"001a1137a5047848dd05157ddaa1\") NIL)(\"application\" \"pdf\" (\"name\" \"test.xml\" \"x-apple-part-url\" \"9D00D9A2-98AB-4EFB-85BA-FB255F8BF3D7\") NIL NIL \"base64\" 4383638 NIL (\"attachment\" (\"filename\" \"test.xml\")) NIL NIL) \"mixed\" (\"boundary\" \"001a1137a5047848e405157ddaa3\") NIL))\r\n")
    assert_equal("FETCH", response.name)
    body = response.data.attr["BODY"]
    assert_equal(nil, body.parts[0].disposition)
    assert_equal(nil, body.parts[0].language)
    assert_equal("ATTACHMENT", body.parts[1].disposition.dsp_type)
    assert_equal("test.xml", body.parts[1].disposition.param["FILENAME"])
    assert_equal(nil, body.parts[1].language)
  end

  # [Bug #13649]
  def test_status
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse("* STATUS INBOX (UIDNEXT 1 UIDVALIDITY 1234)\r\n")
    assert_equal("STATUS", response.name)
    assert_equal("INBOX", response.data.mailbox)
    assert_equal(1234, response.data.attr["UIDVALIDITY"])
    response = parser.parse("* STATUS INBOX (UIDNEXT 1 UIDVALIDITY 1234) \r\n")
    assert_equal("STATUS", response.name)
    assert_equal("INBOX", response.data.mailbox)
    assert_equal(1234, response.data.attr["UIDVALIDITY"])
  end

  # [Bug #10119]
  def test_msg_att_modseq_data
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse("* 1 FETCH (FLAGS (\Seen) MODSEQ (12345) UID 5)\r\n")
    assert_equal(12345, response.data.attr["MODSEQ"])
  end

  def test_continuation_request_without_response_text
    parser = Net::IMAP::ResponseParser.new
    response = parser.parse("+\r\n")
    assert_instance_of(Net::IMAP::ContinuationRequest, response)
    assert_equal(nil, response.data.code)
    assert_equal("", response.data.text)
  end
end
