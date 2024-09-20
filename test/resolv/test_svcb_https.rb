# frozen_string_literal: false
require 'test/unit'
require 'resolv'

class TestResolvSvcbHttps < Test::Unit::TestCase
  # Wraps a RR in answer section
  def wrap_rdata(rrtype, rrclass, rdata)
    [
      "\x00\x00\x00\x00",  # ID/FLAGS
      [0, 1, 0, 0].pack('nnnn'),  # QDCOUNT/ANCOUNT/NSCOUNT/ARCOUNT
      "\x07example\x03com\x00",  # NAME
      [rrtype, rrclass, 0, rdata.bytesize].pack('nnNn'),  # TYPE/CLASS/TTL/RDLENGTH
      rdata,
    ].join.b
  end

  def test_svcparams
    params = Resolv::DNS::SvcParams.new([Resolv::DNS::SvcParam::Mandatory.new([1])])

    assert_equal 1, params.count

    params.add Resolv::DNS::SvcParam::NoDefaultALPN.new
    params.add Resolv::DNS::SvcParam::ALPN.new(%w[h2 h3])

    assert_equal 3, params.count

    assert_equal [1], params[:mandatory].keys
    assert_equal [1], params[0].keys

    assert_equal %w[h2 h3], params[:alpn].protocol_ids
    assert_equal %w[h2 h3], params[1].protocol_ids

    params.delete :mandatory
    params.delete :alpn

    assert_equal 1, params.count

    assert_nil params[:mandatory]
    assert_nil params[1]

    ary = params.each.to_a

    assert_instance_of Resolv::DNS::SvcParam::NoDefaultALPN, ary.first
  end

  def test_svcb
    rr = Resolv::DNS::Resource::IN::SVCB.new(0, 'example.com.')

    assert_equal 0, rr.priority
    assert rr.alias_mode?
    assert !rr.service_mode?
    assert_equal Resolv::DNS::Name.create('example.com.'), rr.target
    assert rr.params.empty?

    rr = Resolv::DNS::Resource::IN::SVCB.new(16, 'example.com.', [
      Resolv::DNS::SvcParam::ALPN.new(%w[h2 h3]),
    ])

    assert_equal 16, rr.priority
    assert !rr.alias_mode?
    assert rr.service_mode?

    assert_equal 1, rr.params.count
    assert_instance_of Resolv::DNS::SvcParam::ALPN, rr.params[:alpn]
  end

  def test_svcb_encode_order
    msg = Resolv::DNS::Message.new(0)
    msg.add_answer(
      'example.com.', 0,
      Resolv::DNS::Resource::IN::SVCB.new(16, 'foo.example.org.', [
        Resolv::DNS::SvcParam::ALPN.new(%w[h2 h3-19]),
        Resolv::DNS::SvcParam::Mandatory.new([4, 1]),
        Resolv::DNS::SvcParam::IPv4Hint.new(['192.0.2.1']),
      ])
    )

    expected = wrap_rdata 64, 1, "\x00\x10\x03foo\x07example\x03org\x00" +
      "\x00\x00\x00\x04\x00\x01\x00\x04" +
      "\x00\x01\x00\x09\x02h2\x05h3-19" +
      "\x00\x04\x00\x04\xc0\x00\x02\x01"

    assert_equal expected, msg.encode
  end

  ## Test vectors from [RFC9460]

  def test_alias_mode
    wire = wrap_rdata 65, 1, "\x00\x00\x03foo\x07example\x03com\x00"
    msg = Resolv::DNS::Message.decode(wire)
    _, _, rr = msg.answer.first

    assert_equal 0, rr.priority
    assert_equal Resolv::DNS::Name.create('foo.example.com.'), rr.target
    assert_equal 0, rr.params.count

    assert_equal wire, msg.encode
  end

  def test_target_name_is_root
    wire = wrap_rdata 64, 1, "\x00\x01\x00"
    msg = Resolv::DNS::Message.decode(wire)
    _, _, rr = msg.answer.first

    assert_equal 1, rr.priority
    assert_equal Resolv::DNS::Name.create('.'), rr.target
    assert_equal 0, rr.params.count

    assert_equal wire, msg.encode
  end

  def test_specifies_port
    wire = wrap_rdata 64, 1, "\x00\x10\x03foo\x07example\x03com\x00" +
      "\x00\x03\x00\x02\x00\x35"
    msg = Resolv::DNS::Message.decode(wire)
    _, _, rr = msg.answer.first

    assert_equal 16, rr.priority
    assert_equal Resolv::DNS::Name.create('foo.example.com.'), rr.target
    assert_equal 1, rr.params.count
    assert_equal 53, rr.params[:port].port

    assert_equal wire, msg.encode
  end

  def test_generic_key
    wire = wrap_rdata 64, 1, "\x00\x01\x03foo\x07example\x03com\x00" +
      "\x02\x9b\x00\x05hello"
    msg = Resolv::DNS::Message.decode(wire)
    _, _, rr = msg.answer.first

    assert_equal 1, rr.priority
    assert_equal Resolv::DNS::Name.create('foo.example.com.'), rr.target
    assert_equal 1, rr.params.count
    assert_equal 'hello', rr.params[:key667].value

    assert_equal wire, msg.encode
  end

  def test_two_ipv6hints
    wire = wrap_rdata 64, 1, "\x00\x01\x03foo\x07example\x03com\x00" +
      "\x00\x06\x00\x20" +
      ("\x20\x01\x0d\xb8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01" +
       "\x20\x01\x0d\xb8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x53\x00\x01")
    msg = Resolv::DNS::Message.decode(wire)
    _, _, rr = msg.answer.first

    assert_equal 1, rr.priority
    assert_equal Resolv::DNS::Name.create('foo.example.com.'), rr.target
    assert_equal 1, rr.params.count
    assert_equal [Resolv::IPv6.create('2001:db8::1'), Resolv::IPv6.create('2001:db8::53:1')],
      rr.params[:ipv6hint].addresses

    assert_equal wire, msg.encode
  end

  def test_ipv6hint_embedded_ipv4
    wire = wrap_rdata 64, 1, "\x00\x01\x07example\x03com\x00" +
      "\x00\x06\x00\x10\x20\x01\x0d\xb8\x01\x22\x03\x44\x00\x00\x00\x00\xc0\x00\x02\x21"
    msg = Resolv::DNS::Message.decode(wire)
    _, _, rr = msg.answer.first

    assert_equal 1, rr.priority
    assert_equal Resolv::DNS::Name.create('example.com.'), rr.target
    assert_equal 1, rr.params.count
    assert_equal [Resolv::IPv6.create('2001:db8:122:344::192.0.2.33')],
      rr.params[:ipv6hint].addresses

    assert_equal wire, msg.encode
  end

  def test_mandatory_alpn_ipv4hint
    wire = wrap_rdata 64, 1, "\x00\x10\x03foo\x07example\x03org\x00" +
      "\x00\x00\x00\x04\x00\x01\x00\x04" +
      "\x00\x01\x00\x09\x02h2\x05h3-19" +
      "\x00\x04\x00\x04\xc0\x00\x02\x01"
    msg = Resolv::DNS::Message.decode(wire)
    _, _, rr = msg.answer.first

    assert_equal 16, rr.priority
    assert_equal Resolv::DNS::Name.create('foo.example.org.'), rr.target
    assert_equal 3, rr.params.count
    assert_equal [1, 4], rr.params[:mandatory].keys
    assert_equal ['h2', 'h3-19'], rr.params[:alpn].protocol_ids
    assert_equal [Resolv::IPv4.create('192.0.2.1')], rr.params[:ipv4hint].addresses

    assert_equal wire, msg.encode
  end

  def test_alpn_comma_backslash
    wire = wrap_rdata 64, 1, "\x00\x10\x03foo\x07example\x03org\x00" +
      "\x00\x01\x00\x0c\x08f\\oo,bar\x02h2"
    msg = Resolv::DNS::Message.decode(wire)
    _, _, rr = msg.answer.first

    assert_equal 16, rr.priority
    assert_equal Resolv::DNS::Name.create('foo.example.org.'), rr.target
    assert_equal 1, rr.params.count
    assert_equal ['f\oo,bar', 'h2'], rr.params[:alpn].protocol_ids

    assert_equal wire, msg.encode
  end

  ## For [RFC9461]

  def test_dohpath
    wire = wrap_rdata 64, 1, "\x00\x01\x03one\x03one\x03one\x03one\x00" +
      "\x00\x01\x00\x03\x02h2" +
      "\x00\x03\x00\x02\x01\xbb" +
      "\x00\x04\x00\x08\x01\x01\x01\x01\x01\x00\x00\x01" +
      "\x00\x06\x00\x20" +
      ("\x26\x06\x47\x00\x47\x00\x00\x00\x00\x00\x00\x00\x00\x00\x11\x11" +
       "\x26\x06\x47\x00\x47\x00\x00\x00\x00\x00\x00\x00\x00\x00\x10\x01") +
      "\x00\x07\x00\x10/dns-query{?dns}"
    msg = Resolv::DNS::Message.decode(wire)
    _, _, rr = msg.answer.first

    assert_equal 1, rr.priority
    assert_equal Resolv::DNS::Name.create('one.one.one.one.'), rr.target
    assert_equal 5, rr.params.count
    assert_equal ['h2'], rr.params[:alpn].protocol_ids
    assert_equal 443, rr.params[:port].port
    assert_equal [Resolv::IPv4.create('1.1.1.1'), Resolv::IPv4.create('1.0.0.1')],
      rr.params[:ipv4hint].addresses
    assert_equal [Resolv::IPv6.create('2606:4700:4700::1111'), Resolv::IPv6.create('2606:4700:4700::1001')],
      rr.params[:ipv6hint].addresses
    assert_equal '/dns-query{?dns}', rr.params[:dohpath].template

    assert_equal wire, msg.encode
  end
end
