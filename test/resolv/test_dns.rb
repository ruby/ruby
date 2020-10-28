# frozen_string_literal: false
require 'test/unit'
require 'resolv'
require 'socket'
require 'tempfile'
require 'minitest/mock'

class TestResolvDNS < Test::Unit::TestCase
  def setup
    @save_do_not_reverse_lookup = BasicSocket.do_not_reverse_lookup
    BasicSocket.do_not_reverse_lookup = true
  end

  def teardown
    BasicSocket.do_not_reverse_lookup = @save_do_not_reverse_lookup
  end

  def with_udp(host, port)
    u = UDPSocket.new
    begin
      u.bind(host, port)
      yield u
    ensure
      u.close
    end
  end

  # [ruby-core:65836]
  def test_resolve_with_2_ndots
    conf = Resolv::DNS::Config.new :nameserver => ['127.0.0.1'], :ndots => 2
    assert conf.single?

    candidates = []
    conf.resolv('example.com') { |candidate, *args|
      candidates << candidate
      raise Resolv::DNS::Config::NXDomain
    }
    n = Resolv::DNS::Name.create 'example.com.'
    assert_equal n, candidates.last
  end

  def test_query_ipv4_address
    begin
      OpenSSL
    rescue LoadError
      skip 'autoload problem. see [ruby-dev:45021][Bug #5786]'
    end if defined?(OpenSSL)

    with_udp('127.0.0.1', 0) {|u|
      _, server_port, _, server_address = u.addr
      begin
        client_thread = Thread.new {
          Resolv::DNS.open(:nameserver_port => [[server_address, server_port]]) {|dns|
            dns.getresources("foo.example.org", Resolv::DNS::Resource::IN::A)
          }
        }
        server_thread = Thread.new {
          msg, (_, client_port, _, client_address) = Timeout.timeout(5) {u.recvfrom(4096)}
          id, word2, qdcount, ancount, nscount, arcount = msg.unpack("nnnnnn")
          qr =     (word2 & 0x8000) >> 15
          opcode = (word2 & 0x7800) >> 11
          aa =     (word2 & 0x0400) >> 10
          tc =     (word2 & 0x0200) >> 9
          rd =     (word2 & 0x0100) >> 8
          ra =     (word2 & 0x0080) >> 7
          z =      (word2 & 0x0070) >> 4
          rcode =   word2 & 0x000f
          rest = msg[12..-1]
          assert_equal(0, qr) # 0:query 1:response
          assert_equal(0, opcode) # 0:QUERY 1:IQUERY 2:STATUS
          assert_equal(0, aa) # Authoritative Answer
          assert_equal(0, tc) # TrunCation
          assert_equal(1, rd) # Recursion Desired
          assert_equal(0, ra) # Recursion Available
          assert_equal(0, z) # Reserved for future use
          assert_equal(0, rcode) # 0:No-error 1:Format-error 2:Server-failure 3:Name-Error 4:Not-Implemented 5:Refused
          assert_equal(1, qdcount) # number of entries in the question section.
          assert_equal(0, ancount) # number of entries in the answer section.
          assert_equal(0, nscount) # number of entries in the authority records section.
          assert_equal(0, arcount) # number of entries in the additional records section.
          name = [3, "foo", 7, "example", 3, "org", 0].pack("Ca*Ca*Ca*C")
          assert_operator(rest, :start_with?, name)
          rest = rest[name.length..-1]
          assert_equal(4, rest.length)
          qtype, _ = rest.unpack("nn")
          assert_equal(1, qtype) # A
          assert_equal(1, qtype) # IN
          id = id
          qr = 1
          opcode = opcode
          aa = 0
          tc = 0
          rd = rd
          ra = 1
          z = 0
          rcode = 0
          qdcount = 0
          ancount = 1
          nscount = 0
          arcount = 0
          word2 = (qr << 15) |
                  (opcode << 11) |
                  (aa << 10) |
                  (tc << 9) |
                  (rd << 8) |
                  (ra << 7) |
                  (z << 4) |
                  rcode
          msg = [id, word2, qdcount, ancount, nscount, arcount].pack("nnnnnn")
          type = 1
          klass = 1
          ttl = 3600
          rdlength = 4
          rdata = [192,0,2,1].pack("CCCC") # 192.0.2.1 (TEST-NET address) RFC 3330
          rr = [name, type, klass, ttl, rdlength, rdata].pack("a*nnNna*")
          msg << rr
          u.send(msg, 0, client_address, client_port)
        }
        result, _ = assert_join_threads([client_thread, server_thread])
        assert_instance_of(Array, result)
        assert_equal(1, result.length)
        rr = result[0]
        assert_instance_of(Resolv::DNS::Resource::IN::A, rr)
        assert_instance_of(Resolv::IPv4, rr.address)
        assert_equal("192.0.2.1", rr.address.to_s)
        assert_equal(3600, rr.ttl)
      end
    }
  end

  def test_query_ipv4_address_timeout
    with_udp('127.0.0.1', 0) {|u|
      _, port , _, host = u.addr
      start = nil
      rv = Resolv::DNS.open(:nameserver_port => [[host, port]]) {|dns|
        dns.timeouts = 0.1
        start = Time.now
        dns.getresources("foo.example.org", Resolv::DNS::Resource::IN::A)
      }
      t2 = Time.now
      diff = t2 - start
      assert rv.empty?, "unexpected: #{rv.inspect} (expected empty)"
      assert_operator 0.1, :<=, diff

      rv = Resolv::DNS.open(:nameserver_port => [[host, port]]) {|dns|
        dns.timeouts = [ 0.1, 0.2 ]
        start = Time.now
        dns.getresources("foo.example.org", Resolv::DNS::Resource::IN::A)
      }
      t2 = Time.now
      diff = t2 - start
      assert rv.empty?, "unexpected: #{rv.inspect} (expected empty)"
      assert_operator 0.3, :<=, diff
    }
  end

  def test_no_server
    u = UDPSocket.new
    u.bind("127.0.0.1", 0)
    _, port, _, host = u.addr
    u.close
    # A race condition here.
    # Another program may use the port.
    # But no way to prevent it.
    begin
      Timeout.timeout(5) do
        Resolv::DNS.open(:nameserver_port => [[host, port]]) {|dns|
          assert_equal([], dns.getresources("test-no-server.example.org", Resolv::DNS::Resource::IN::A))
        }
      end
    rescue Timeout::Error
      if RUBY_PLATFORM.match?(/mingw/)
        # cannot repo locally
        skip 'Timeout Error on MinGW CI'
      else
        raise Timeout::Error
      end
    end
  end

  def test_invalid_byte_comment
    bug9273 = '[ruby-core:59239] [Bug #9273]'
    Tempfile.create('resolv_test_dns_') do |tmpfile|
      tmpfile.print("\xff\x00\x40")
      tmpfile.close
      assert_nothing_raised(ArgumentError, bug9273) do
        Resolv::DNS::Config.parse_resolv_conf(tmpfile.path)
      end
    end
  end

  def test_resolv_conf_by_command
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        assert_raise(Errno::ENOENT, Errno::EINVAL) do
          Resolv::DNS::Config.parse_resolv_conf("|echo foo")
        end
      end
    end
  end

  def test_dots_diffences
    name1 = Resolv::DNS::Name.create("example.org")
    name2 = Resolv::DNS::Name.create("ex.ampl.eo.rg")
    assert_not_equal(name1, name2, "different dots")
  end

  def test_case_insensitive_name
    bug10550 = '[ruby-core:66498] [Bug #10550]'
    lower = Resolv::DNS::Name.create("ruby-lang.org")
    upper = Resolv::DNS::Name.create("Ruby-Lang.org")
    assert_equal(lower, upper, bug10550)
  end

  def test_ipv6_name
    addr = Resolv::IPv6.new("\0"*16)
    labels = addr.to_name.to_a
    expected = (['0'] * 32 + ['ip6', 'arpa']).map {|label| Resolv::DNS::Label::Str.new(label) }
    assert_equal(expected, labels)
  end

  def test_ipv6_create
    ref = '[Bug #11910] [ruby-core:72559]'
    assert_instance_of Resolv::IPv6, Resolv::IPv6.create('::1'), ref
    assert_instance_of Resolv::IPv6, Resolv::IPv6.create('::1:127.0.0.1'), ref
  end

  def test_ipv6_to_s
    test_cases = [
      ["2001::abcd:abcd:abcd", "2001::ABcd:abcd:ABCD"],
      ["2001:db8::1", "2001:db8::0:1"],
      ["::", "0:0:0:0:0:0:0:0"],
      ["2001::", "2001::0"],
      ["2001:db8::1:1:1:1:1", "2001:db8:0:1:1:1:1:1"],
      ["1::1:0:0:0:1", "1:0:0:1:0:0:0:1"],
      ["1::1:0:0:1", "1:0:0:0:1:0:0:1"],
    ]

    test_cases.each do |expected, ipv6|
      assert_equal expected, Resolv::IPv6.create(ipv6).to_s
    end
  end

  def test_ipv6_should_be_16
    ref = '[rubygems:1626]'

    broken_message =
      "\0\0\0\0\0\0\0\0\0\0\0\1" \
      "\x03ns2\bdnsimple\x03com\x00" \
      "\x00\x1C\x00\x01\x00\x02OD" \
      "\x00\x10$\x00\xCB\x00 I\x00\x01\x00\x00\x00\x00"

    e = assert_raise_with_message(Resolv::DNS::DecodeError, /IPv6 address must be 16 bytes/, ref) do
      Resolv::DNS::Message.decode broken_message
    end
    assert_kind_of(ArgumentError, e.cause)
  end

  def test_too_big_label_address
    n = 2000
    m = Resolv::DNS::Message::MessageEncoder.new {|msg|
      2.times {
        n.times {|i| msg.put_labels(["foo#{i}"]) }
      }
    }
    Resolv::DNS::Message::MessageDecoder.new(m.to_s) {|msg|
      2.times {
        n.times {|i|
          assert_equal(["foo#{i}"], msg.get_labels.map {|label| label.to_s })
        }
      }
    }
    assert_operator(2**14, :<, m.to_s.length)
  end

  def assert_no_fd_leak
    socket = assert_throw(self) do |tag|
      Resolv::DNS.stub(:bind_random_port, ->(s, *) {throw(tag, s)}) do
        yield.getname("8.8.8.8")
      end
    end

    assert_predicate(socket, :closed?, "file descriptor leaked")
  end

  def test_no_fd_leak_connected
    assert_no_fd_leak {Resolv::DNS.new(nameserver_port: [['127.0.0.1', 53]])}
  end

  def test_no_fd_leak_unconnected
    assert_no_fd_leak {Resolv::DNS.new}
  end

  def test_each_name
    dns = Resolv::DNS.new
    def dns.each_resource(name, typeclass)
      yield typeclass.new(name)
    end

    dns.each_name('127.0.0.1') do |ptr|
      assert_equal('1.0.0.127.in-addr.arpa', ptr.to_s)
    end
    dns.each_name(Resolv::IPv4.create('127.0.0.1')) do |ptr|
      assert_equal('1.0.0.127.in-addr.arpa', ptr.to_s)
    end
    dns.each_name('::1') do |ptr|
      assert_equal('1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa', ptr.to_s)
    end
    dns.each_name(Resolv::IPv6.create('::1')) do |ptr|
      assert_equal('1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa', ptr.to_s)
    end
    dns.each_name(Resolv::DNS::Name.create('1.0.0.127.in-addr.arpa.')) do |ptr|
      assert_equal('1.0.0.127.in-addr.arpa', ptr.to_s)
    end
    assert_raise(Resolv::ResolvError) { dns.each_name('example.com') }
  end
end
