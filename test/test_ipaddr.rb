# frozen_string_literal: true
require 'test/unit'
require 'ipaddr'

class TC_IPAddr < Test::Unit::TestCase
  def test_s_new
    [
      ["3FFE:505:ffff::/48"],
      ["0:0:0:1::"],
      ["2001:200:300::/48"],
      ["2001:200:300::192.168.1.2/48"],
      ["1:2:3:4:5:6:7::"],
      ["::2:3:4:5:6:7:8"],
    ].each { |args|
      assert_nothing_raised {
        IPAddr.new(*args)
      }
    }

    a = IPAddr.new
    assert_equal("::", a.to_s)
    assert_equal("0000:0000:0000:0000:0000:0000:0000:0000", a.to_string)
    assert_equal("::/128", a.cidr)
    assert_equal(Socket::AF_INET6, a.family)
    assert_equal(128, a.prefix)

    a = IPAddr.new("0123:4567:89ab:cdef:0ABC:DEF0:1234:5678")
    assert_equal("123:4567:89ab:cdef:abc:def0:1234:5678", a.to_s)
    assert_equal("0123:4567:89ab:cdef:0abc:def0:1234:5678", a.to_string)
    assert_equal("123:4567:89ab:cdef:abc:def0:1234:5678/128", a.cidr)
    assert_equal(Socket::AF_INET6, a.family)
    assert_equal(128, a.prefix)

    a = IPAddr.new("3ffe:505:2::/48")
    assert_equal("3ffe:505:2::", a.to_s)
    assert_equal("3ffe:0505:0002:0000:0000:0000:0000:0000", a.to_string)
    assert_equal("3ffe:505:2::/48", a.cidr)
    assert_equal(Socket::AF_INET6, a.family)
    assert_equal(false, a.ipv4?)
    assert_equal(true, a.ipv6?)
    assert_equal("#<IPAddr: IPv6:3ffe:0505:0002:0000:0000:0000:0000:0000/ffff:ffff:ffff:0000:0000:0000:0000:0000>", a.inspect)
    assert_equal(48, a.prefix)

    a = IPAddr.new("3ffe:505:2::/ffff:ffff:ffff::")
    assert_equal("3ffe:505:2::", a.to_s)
    assert_equal("3ffe:0505:0002:0000:0000:0000:0000:0000", a.to_string)
    assert_equal("3ffe:505:2::/48", a.cidr)
    assert_equal(Socket::AF_INET6, a.family)
    assert_equal(48, a.prefix)
    assert_nil(a.zone_id)

    a = IPAddr.new("fe80::1%ab0")
    assert_equal("fe80::1%ab0", a.to_s)
    assert_equal("fe80:0000:0000:0000:0000:0000:0000:0001%ab0", a.to_string)
    assert_equal(Socket::AF_INET6, a.family)
    assert_equal(false, a.ipv4?)
    assert_equal(true, a.ipv6?)
    assert_equal("#<IPAddr: IPv6:fe80:0000:0000:0000:0000:0000:0000:0001%ab0/ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff>", a.inspect)
    assert_equal(128, a.prefix)
    assert_equal('%ab0', a.zone_id)

    a = IPAddr.new("0.0.0.0")
    assert_equal("0.0.0.0", a.to_s)
    assert_equal("0.0.0.0", a.to_string)
    assert_equal("0.0.0.0/32", a.cidr)
    assert_equal(Socket::AF_INET, a.family)
    assert_equal(32, a.prefix)

    a = IPAddr.new("192.168.1.2")
    assert_equal("192.168.1.2", a.to_s)
    assert_equal("192.168.1.2", a.to_string)
    assert_equal("192.168.1.2/32", a.cidr)
    assert_equal(Socket::AF_INET, a.family)
    assert_equal(true, a.ipv4?)
    assert_equal(false, a.ipv6?)
    assert_equal(32, a.prefix)

    a = IPAddr.new("192.168.1.2/26")
    assert_equal("192.168.1.0", a.to_s)
    assert_equal("192.168.1.0", a.to_string)
    assert_equal("192.168.1.0/26", a.cidr)
    assert_equal(Socket::AF_INET, a.family)
    assert_equal("#<IPAddr: IPv4:192.168.1.0/255.255.255.192>", a.inspect)
    assert_equal(26, a.prefix)

    a = IPAddr.new("192.168.1.2/255.255.255.0")
    assert_equal("192.168.1.0", a.to_s)
    assert_equal("192.168.1.0", a.to_string)
    assert_equal("192.168.1.0/24", a.cidr)
    assert_equal(Socket::AF_INET, a.family)
    assert_equal(24, a.prefix)

    (0..32).each do |prefix|
      assert_equal(prefix, IPAddr.new("10.20.30.40/#{prefix}").prefix)
    end
    (0..128).each do |prefix|
      assert_equal(prefix, IPAddr.new("1:2:3:4:5:6:7:8/#{prefix}").prefix)
    end

    assert_equal("0:0:0:1::", IPAddr.new("0:0:0:1::").to_s)
    assert_equal("2001:200:300::", IPAddr.new("2001:200:300::/48").to_s)

    assert_equal("2001:200:300::", IPAddr.new("[2001:200:300::]/48").to_s)
    assert_equal("1:2:3:4:5:6:7:0", IPAddr.new("1:2:3:4:5:6:7::").to_s)
    assert_equal("0:2:3:4:5:6:7:8", IPAddr.new("::2:3:4:5:6:7:8").to_s)

    assert_raise(IPAddr::InvalidAddressError) { IPAddr.new("192.168.0.256") }
    assert_raise(IPAddr::InvalidAddressError) { IPAddr.new("192.168.0.011") }
    assert_raise(IPAddr::InvalidAddressError) { IPAddr.new("fe80::1%") }
    assert_raise(IPAddr::InvalidAddressError) { IPAddr.new("fe80::1%]") }
    assert_raise(IPAddr::InvalidAddressError) { IPAddr.new("[192.168.1.2]/120") }
    assert_raise(IPAddr::InvalidAddressError) { IPAddr.new("[2001:200:300::]\nINVALID") }
    assert_raise(IPAddr::InvalidAddressError) { IPAddr.new("192.168.0.1/32\nINVALID") }
    assert_raise(IPAddr::InvalidAddressError) { IPAddr.new("192.168.0.1/32/20") }
    assert_raise(IPAddr::InvalidPrefixError) { IPAddr.new("192.168.0.1/032") }
    assert_raise(IPAddr::InvalidPrefixError) { IPAddr.new("::1/0128") }
    assert_raise(IPAddr::InvalidPrefixError) { IPAddr.new("::1/255.255.255.0") }
    assert_raise(IPAddr::InvalidPrefixError) { IPAddr.new("::1/129") }
    assert_raise(IPAddr::InvalidPrefixError) { IPAddr.new("192.168.0.1/33") }
    assert_raise(IPAddr::InvalidPrefixError) { IPAddr.new("192.168.0.1/255.255.255.1") }
    assert_raise(IPAddr::AddressFamilyError) { IPAddr.new(1) }
    assert_raise(IPAddr::AddressFamilyError) { IPAddr.new("::ffff:192.168.1.2/120", Socket::AF_INET) }
  end

  def test_s_new_ntoh
    addr = ''
    IPAddr.new("1234:5678:9abc:def0:1234:5678:9abc:def0").hton.each_byte { |c|
      addr += sprintf("%02x", c)
    }
    assert_equal("123456789abcdef0123456789abcdef0", addr)
    addr = ''
    IPAddr.new("123.45.67.89").hton.each_byte { |c|
      addr += sprintf("%02x", c)
    }
    assert_equal(sprintf("%02x%02x%02x%02x", 123, 45, 67, 89), addr)
    a = IPAddr.new("3ffe:505:2::")
    assert_equal("3ffe:505:2::", IPAddr.new_ntoh(a.hton).to_s)
    a = IPAddr.new("192.168.2.1")
    assert_equal("192.168.2.1", IPAddr.new_ntoh(a.hton).to_s)
  end

  def test_ntop
    # IPv4
    assert_equal("192.168.1.1", IPAddr.ntop("\xC0\xA8\x01\x01".b))
    assert_equal("10.231.140.171", IPAddr.ntop("\x0A\xE7\x8C\xAB".b))
    # IPv6
    assert_equal("0000:0000:0000:0000:0000:0000:0000:0001",
                 IPAddr.ntop("\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01".b))
    assert_equal("fe80:0000:0000:0000:f09f:9985:f09f:9986",
                 IPAddr.ntop("\xFE\x80\x00\x00\x00\x00\x00\x00\xF0\x9F\x99\x85\xF0\x9F\x99\x86".b))

    # Invalid parameters
    ## wrong length
    assert_raise(IPAddr::AddressFamilyError) {
      IPAddr.ntop("192.168.1.1".b)
    }
    assert_raise(IPAddr::AddressFamilyError) {
      IPAddr.ntop("\xC0\xA8\x01\xFF1".b)
    }
    ## UTF-8
    assert_raise(IPAddr::InvalidAddressError) {
      IPAddr.ntop("192.168.1.1")
    }
    assert_raise(IPAddr::InvalidAddressError) {
      IPAddr.ntop("\x0A\x0A\x0A\x0A")
    }
    assert_raise(IPAddr::InvalidAddressError) {
      IPAddr.ntop("\x0A\xE7\x8C\xAB")
    }
    assert_raise(IPAddr::InvalidAddressError) {
      IPAddr.ntop("\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01")
    }
    assert_raise(IPAddr::InvalidAddressError) {
      IPAddr.ntop("\xFE\x80\x00\x00\x00\x00\x00\x00\xF0\x9F\x99\x85\xF0\x9F\x99\x86")
    }
  end

  def test_ipv4_compat
    a = IPAddr.new("::192.168.1.2")
    assert_equal("::192.168.1.2", a.to_s)
    assert_equal("0000:0000:0000:0000:0000:0000:c0a8:0102", a.to_string)
    assert_equal(Socket::AF_INET6, a.family)
    assert_warning(/obsolete/) {
      assert_predicate(a, :ipv4_compat?)
    }
    b = a.native
    assert_equal("192.168.1.2", b.to_s)
    assert_equal(Socket::AF_INET, b.family)
    assert_warning(/obsolete/) {
      assert_not_predicate(b, :ipv4_compat?)
    }

    a = IPAddr.new("192.168.1.2")
    assert_warning(/obsolete/) {
      b = a.ipv4_compat
    }
    assert_equal("::192.168.1.2", b.to_s)
    assert_equal(Socket::AF_INET6, b.family)
  end

  def test_ipv4_mapped
    a = IPAddr.new("::ffff:192.168.1.2")
    assert_equal("::ffff:192.168.1.2", a.to_s)
    assert_equal("0000:0000:0000:0000:0000:ffff:c0a8:0102", a.to_string)
    assert_equal(Socket::AF_INET6, a.family)
    assert_equal(true, a.ipv4_mapped?)
    b = a.native
    assert_equal("192.168.1.2", b.to_s)
    assert_equal(Socket::AF_INET, b.family)
    assert_equal(false, b.ipv4_mapped?)

    a = IPAddr.new("192.168.1.2")
    b = a.ipv4_mapped
    assert_equal("::ffff:192.168.1.2", b.to_s)
    assert_equal(Socket::AF_INET6, b.family)
  end

  def test_reverse
    assert_equal("f.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.2.0.0.0.5.0.5.0.e.f.f.3.ip6.arpa", IPAddr.new("3ffe:505:2::f").reverse)
    assert_equal("1.2.168.192.in-addr.arpa", IPAddr.new("192.168.2.1").reverse)
  end

  def test_ip6_arpa
    assert_equal("f.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.2.0.0.0.5.0.5.0.e.f.f.3.ip6.arpa", IPAddr.new("3ffe:505:2::f").ip6_arpa)
    assert_raise(IPAddr::InvalidAddressError) {
      IPAddr.new("192.168.2.1").ip6_arpa
    }
  end

  def test_ip6_int
    assert_equal("f.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.2.0.0.0.5.0.5.0.e.f.f.3.ip6.int", IPAddr.new("3ffe:505:2::f").ip6_int)
    assert_raise(IPAddr::InvalidAddressError) {
      IPAddr.new("192.168.2.1").ip6_int
    }
  end

  def test_prefix_writer
    a = IPAddr.new("192.168.1.2")
    ["1", "255.255.255.0", "ffff:ffff:ffff:ffff::", nil, 1.0, -1, 33].each { |x|
      assert_raise(IPAddr::InvalidPrefixError) { a.prefix = x }
    }
    a = IPAddr.new("1:2:3:4:5:6:7:8")
    ["1", "255.255.255.0", "ffff:ffff:ffff:ffff::", nil, 1.0, -1, 129].each { |x|
      assert_raise(IPAddr::InvalidPrefixError) { a.prefix = x }
    }

    a = IPAddr.new("192.168.1.2")
    a.prefix = 26
    assert_equal(26, a.prefix)
    assert_equal("192.168.1.0", a.to_s)

    a = IPAddr.new("1:2:3:4:5:6:7:8")
    a.prefix = 52
    assert_equal(52, a.prefix)
    assert_equal("1:2:3::", a.to_s)
  end

  def test_to_s
    assert_equal("3ffe:0505:0002:0000:0000:0000:0000:0001", IPAddr.new("3ffe:505:2::1").to_string)
    assert_equal("3ffe:505:2::1", IPAddr.new("3ffe:505:2::1").to_s)
  end

  def test_netmask
    a = IPAddr.new("192.168.1.2/8")
    assert_equal(a.netmask, "255.0.0.0")

    a = IPAddr.new("192.168.1.2/16")
    assert_equal(a.netmask, "255.255.0.0")

    a = IPAddr.new("192.168.1.2/24")
    assert_equal(a.netmask, "255.255.255.0")
  end

  def test_wildcard_mask
    a = IPAddr.new("192.168.1.2/1")
    assert_equal(a.wildcard_mask, "127.255.255.255")

    a = IPAddr.new("192.168.1.2/8")
    assert_equal(a.wildcard_mask, "0.255.255.255")

    a = IPAddr.new("192.168.1.2/16")
    assert_equal(a.wildcard_mask, "0.0.255.255")

    a = IPAddr.new("192.168.1.2/24")
    assert_equal(a.wildcard_mask, "0.0.0.255")

    a = IPAddr.new("192.168.1.2/32")
    assert_equal(a.wildcard_mask, "0.0.0.0")

    a = IPAddr.new("3ffe:505:2::/48")
    assert_equal(a.wildcard_mask, "0000:0000:0000:ffff:ffff:ffff:ffff:ffff")

    a = IPAddr.new("3ffe:505:2::/128")
    assert_equal(a.wildcard_mask, "0000:0000:0000:0000:0000:0000:0000:0000")
  end

  def test_zone_id
    a = IPAddr.new("192.168.1.2")
    assert_raise(IPAddr::InvalidAddressError) { a.zone_id = '%ab0' }
    assert_raise(IPAddr::InvalidAddressError) { a.zone_id }

    a = IPAddr.new("1:2:3:4:5:6:7:8")
    a.zone_id = '%ab0'
    assert_equal('%ab0', a.zone_id)
    assert_equal("1:2:3:4:5:6:7:8%ab0", a.to_s)
    assert_raise(IPAddr::InvalidAddressError) { a.zone_id = '%' }
  end

  def test_to_range
    a1 = IPAddr.new("127.0.0.1")
    range = a1..a1
    assert_equal(range, a1.to_range)
    assert_equal(range, a1.freeze.to_range)

    a2 = IPAddr.new("192.168.0.1/16")
    range = IPAddr.new("192.168.0.0")..IPAddr.new("192.168.255.255")
    assert_equal(range, a2.to_range)
    assert_equal(range, a2.freeze.to_range)

    a3 = IPAddr.new("3ffe:505:2::1")
    range = a3..a3
    assert_equal(range, a3.to_range)
    assert_equal(range, a3.freeze.to_range)

    a4 = IPAddr.new("::ffff/127")
    range = IPAddr.new("::fffe")..IPAddr.new("::ffff")
    assert_equal(range, a4.to_range)
    assert_equal(range, a4.freeze.to_range)
  end
end

class TC_Operator < Test::Unit::TestCase

  IN6MASK32  = "ffff:ffff::"
  IN6MASK128 = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"

  def setup
    @in6_addr_any = IPAddr.new()
    @a = IPAddr.new("3ffe:505:2::/48")
    @b = IPAddr.new("0:0:0:1::")
    @c = IPAddr.new(IN6MASK32)
    @inconvertible_range = 1..5
    @inconvertible_string = "sometext"
  end
  alias set_up setup

  def test_or
    assert_equal("3ffe:505:2:1::", (@a | @b).to_s)
    a = @a
    a |= @b
    assert_equal("3ffe:505:2:1::", a.to_s)
    assert_equal("3ffe:505:2::", @a.to_s)
    assert_equal("3ffe:505:2:1::",
                 (@a | 0x00000000000000010000000000000000).to_s)
  end

  def test_and
    assert_equal("3ffe:505::", (@a & @c).to_s)
    a = @a
    a &= @c
    assert_equal("3ffe:505::", a.to_s)
    assert_equal("3ffe:505:2::", @a.to_s)
    assert_equal("3ffe:505::", (@a & 0xffffffff000000000000000000000000).to_s)
  end

  def test_shift_right
    assert_equal("0:3ffe:505:2::", (@a >> 16).to_s)
    a = @a
    a >>= 16
    assert_equal("0:3ffe:505:2::", a.to_s)
    assert_equal("3ffe:505:2::", @a.to_s)
  end

  def test_shift_left
    assert_equal("505:2::", (@a << 16).to_s)
    a = @a
    a <<= 16
    assert_equal("505:2::", a.to_s)
    assert_equal("3ffe:505:2::", @a.to_s)
  end

  def test_carrot
    a = ~@in6_addr_any
    assert_equal(IN6MASK128, a.to_s)
    assert_equal("::", @in6_addr_any.to_s)
  end

  def test_equal
    assert_equal(true, @a == IPAddr.new("3FFE:505:2::"))
    assert_equal(true, @a == IPAddr.new("3ffe:0505:0002::"))
    assert_equal(true, @a == IPAddr.new("3ffe:0505:0002:0:0:0:0:0"))
    assert_equal(false, @a == IPAddr.new("3ffe:505:3::"))
    assert_equal(true, @a != IPAddr.new("3ffe:505:3::"))
    assert_equal(false, @a != IPAddr.new("3ffe:505:2::"))
    assert_equal(false, @a == @inconvertible_range)
    assert_equal(false, @a == @inconvertible_string)
  end

  def test_compare
    assert_equal(nil, @a <=> @inconvertible_range)
    assert_equal(nil, @a <=> @inconvertible_string)
  end

  def test_mask
    a = @a.mask(32)
    assert_equal("3ffe:505::", a.to_s)
    assert_equal("3ffe:505::", @a.mask("ffff:ffff::").to_s)
    assert_equal("3ffe:505:2::", @a.to_s)
    a = IPAddr.new("192.168.2.0/24")
    assert_equal("192.168.0.0", a.mask(16).to_s)
    assert_equal("192.168.0.0", a.mask("255.255.0.0").to_s)
    assert_equal("192.168.2.0", a.to_s)
    assert_raise(IPAddr::InvalidPrefixError) {a.mask("255.255.0.255")}
    assert_raise(IPAddr::InvalidPrefixError) {@a.mask("ffff:1::")}
  end

  def test_include?
    assert_equal(true, @a.include?(IPAddr.new("3ffe:505:2::")))
    assert_equal(true, @a.include?(IPAddr.new("3ffe:505:2::1")))
    assert_equal(false, @a.include?(IPAddr.new("3ffe:505:3::")))
    net1 = IPAddr.new("192.168.2.0/24")
    assert_equal(true, net1.include?(IPAddr.new("192.168.2.0")))
    assert_equal(true, net1.include?(IPAddr.new("192.168.2.255")))
    assert_equal(false, net1.include?(IPAddr.new("192.168.3.0")))
    assert_equal(true, net1.include?(IPAddr.new("192.168.2.0/28")))
    assert_equal(false, net1.include?(IPAddr.new("192.168.2.0/16")))
    # test with integer parameter
    int = (192 << 24) + (168 << 16) + (2 << 8) + 13

    assert_equal(true, net1.include?(int))
    assert_equal(false, net1.include?(int+255))

  end

  def test_native_coerce_mask_addr
    assert_equal(IPAddr.new("0.0.0.2/255.255.255.255"), IPAddr.new("::2").native)
    assert_equal(IPAddr.new("0.0.0.2/255.255.255.255").to_range, IPAddr.new("::2").native.to_range)
  end

  def test_loopback?
    assert_equal(true,  IPAddr.new('127.0.0.1').loopback?)
    assert_equal(true,  IPAddr.new('127.127.1.1').loopback?)
    assert_equal(false, IPAddr.new('0.0.0.0').loopback?)
    assert_equal(false, IPAddr.new('192.168.2.0').loopback?)
    assert_equal(false, IPAddr.new('255.0.0.0').loopback?)
    assert_equal(true,  IPAddr.new('::1').loopback?)
    assert_equal(false, IPAddr.new('::').loopback?)
    assert_equal(false, IPAddr.new('3ffe:505:2::1').loopback?)

    assert_equal(true,  IPAddr.new('::ffff:127.0.0.1').loopback?)
    assert_equal(true,  IPAddr.new('::ffff:127.127.1.1').loopback?)
    assert_equal(false, IPAddr.new('::ffff:0.0.0.0').loopback?)
    assert_equal(false, IPAddr.new('::ffff:192.168.2.0').loopback?)
    assert_equal(false, IPAddr.new('::ffff:255.0.0.0').loopback?)
  end

  def test_private?
    assert_equal(false, IPAddr.new('0.0.0.0').private?)
    assert_equal(false, IPAddr.new('127.0.0.1').private?)

    assert_equal(false, IPAddr.new('8.8.8.8').private?)
    assert_equal(true,  IPAddr.new('10.0.0.0').private?)
    assert_equal(true,  IPAddr.new('10.255.255.255').private?)
    assert_equal(false, IPAddr.new('11.255.1.1').private?)

    assert_equal(false, IPAddr.new('172.15.255.255').private?)
    assert_equal(true,  IPAddr.new('172.16.0.0').private?)
    assert_equal(true,  IPAddr.new('172.31.255.255').private?)
    assert_equal(false, IPAddr.new('172.32.0.0').private?)

    assert_equal(false, IPAddr.new('190.168.0.0').private?)
    assert_equal(true,  IPAddr.new('192.168.0.0').private?)
    assert_equal(true,  IPAddr.new('192.168.255.255').private?)
    assert_equal(false, IPAddr.new('192.169.0.0').private?)

    assert_equal(false, IPAddr.new('169.254.0.1').private?)

    assert_equal(false, IPAddr.new('::1').private?)
    assert_equal(false, IPAddr.new('::').private?)

    assert_equal(false, IPAddr.new('fb84:8bf7:e905::1').private?)
    assert_equal(true,  IPAddr.new('fc84:8bf7:e905::1').private?)
    assert_equal(true,  IPAddr.new('fd84:8bf7:e905::1').private?)
    assert_equal(false, IPAddr.new('fe84:8bf7:e905::1').private?)

    assert_equal(false, IPAddr.new('::ffff:0.0.0.0').private?)
    assert_equal(false, IPAddr.new('::ffff:127.0.0.1').private?)

    assert_equal(false, IPAddr.new('::ffff:8.8.8.8').private?)
    assert_equal(true,  IPAddr.new('::ffff:10.0.0.0').private?)
    assert_equal(true,  IPAddr.new('::ffff:10.255.255.255').private?)
    assert_equal(false, IPAddr.new('::ffff:11.255.1.1').private?)

    assert_equal(false, IPAddr.new('::ffff:172.15.255.255').private?)
    assert_equal(true,  IPAddr.new('::ffff:172.16.0.0').private?)
    assert_equal(true,  IPAddr.new('::ffff:172.31.255.255').private?)
    assert_equal(false, IPAddr.new('::ffff:172.32.0.0').private?)

    assert_equal(false, IPAddr.new('::ffff:190.168.0.0').private?)
    assert_equal(true,  IPAddr.new('::ffff:192.168.0.0').private?)
    assert_equal(true,  IPAddr.new('::ffff:192.168.255.255').private?)
    assert_equal(false, IPAddr.new('::ffff:192.169.0.0').private?)

    assert_equal(false, IPAddr.new('::ffff:169.254.0.1').private?)
  end

  def test_link_local?
    assert_equal(false, IPAddr.new('0.0.0.0').link_local?)
    assert_equal(false, IPAddr.new('127.0.0.1').link_local?)
    assert_equal(false, IPAddr.new('10.0.0.0').link_local?)
    assert_equal(false, IPAddr.new('172.16.0.0').link_local?)
    assert_equal(false, IPAddr.new('192.168.0.0').link_local?)

    assert_equal(true,  IPAddr.new('169.254.1.1').link_local?)
    assert_equal(true,  IPAddr.new('169.254.254.255').link_local?)

    assert_equal(false, IPAddr.new('::1').link_local?)
    assert_equal(false, IPAddr.new('::').link_local?)
    assert_equal(false, IPAddr.new('fb84:8bf7:e905::1').link_local?)

    assert_equal(true,  IPAddr.new('fe80::dead:beef:cafe:1234').link_local?)

    assert_equal(false, IPAddr.new('::ffff:0.0.0.0').link_local?)
    assert_equal(false, IPAddr.new('::ffff:127.0.0.1').link_local?)
    assert_equal(false, IPAddr.new('::ffff:10.0.0.0').link_local?)
    assert_equal(false, IPAddr.new('::ffff:172.16.0.0').link_local?)
    assert_equal(false, IPAddr.new('::ffff:192.168.0.0').link_local?)

    assert_equal(true,  IPAddr.new('::ffff:169.254.1.1').link_local?)
    assert_equal(true,  IPAddr.new('::ffff:169.254.254.255').link_local?)
  end

  def test_hash
    a1 = IPAddr.new('192.168.2.0')
    a2 = IPAddr.new('192.168.2.0')
    a3 = IPAddr.new('3ffe:505:2::1')
    a4 = IPAddr.new('3ffe:505:2::1')
    a5 = IPAddr.new('127.0.0.1')
    a6 = IPAddr.new('::1')
    a7 = IPAddr.new('192.168.2.0/25')
    a8 = IPAddr.new('192.168.2.0/25')

    h = { a1 => 'ipv4', a2 => 'ipv4', a3 => 'ipv6', a4 => 'ipv6', a5 => 'ipv4', a6 => 'ipv6', a7 => 'ipv4', a8 => 'ipv4'}
    assert_equal(5, h.size)
    assert_equal('ipv4', h[a1])
    assert_equal('ipv4', h[a2])
    assert_equal('ipv6', h[a3])
    assert_equal('ipv6', h[a4])

    require 'set'
    s = Set[a1, a2, a3, a4, a5, a6, a7, a8]
    assert_equal(5, s.size)
    assert_equal(true, s.include?(a1))
    assert_equal(true, s.include?(a2))
    assert_equal(true, s.include?(a3))
    assert_equal(true, s.include?(a4))
    assert_equal(true, s.include?(a5))
    assert_equal(true, s.include?(a6))
  end
end
