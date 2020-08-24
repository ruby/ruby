# frozen_string_literal: false
require 'test/unit'
require 'resolv'
require 'socket'
require 'tempfile'

class TestResolvAddr < Test::Unit::TestCase
  def test_invalid_ipv4_address
    assert_not_match(Resolv::IPv4::Regex, "1.2.3.256", "[ruby-core:29501]")
    1000.times {|i|
      if i < 256
        assert_match(Resolv::IPv4::Regex, "#{i}.#{i}.#{i}.#{i}")
      else
        assert_not_match(Resolv::IPv4::Regex, "#{i}.#{i}.#{i}.#{i}")
      end
    }
  end

  def test_valid_ipv6_link_local_address
    bug17112 = "[ruby-core:99539]"
    assert_not_match(Resolv::IPv6::Regex, "fe80::1%", bug17112)
    assert_not_match(Resolv::IPv6::Regex, "fe80:2:3:4:5:6:7:8%", bug17112)
    assert_not_match(Resolv::IPv6::Regex, "fe90::1%em1", bug17112)
    assert_not_match(Resolv::IPv6::Regex, "1:2:3:4:5:6:7:8%em1", bug17112)
    assert_match(Resolv::IPv6::Regex, "fe80:2:3:4:5:6:7:8%em1", bug17112)
    assert_match(Resolv::IPv6::Regex, "fe80::20d:3aff:fe7d:9760%eth0", bug17112)
    assert_match(Resolv::IPv6::Regex, "fe80::1%em1", bug17112)
  end

  def test_valid_socket_ip_address_list
    Socket.ip_address_list.each do |addr|
      ip = addr.ip_address
      assert_match(Resolv::AddressRegex, ip)
      assert_equal(ip, Resolv.getaddress(ip))
    end
  end

  def test_invalid_byte_comment
    bug9273 = '[ruby-core:59239] [Bug #9273]'
    Tempfile.create('resolv_test_addr_') do |tmpfile|
      tmpfile.print("\xff\x00\x40")
      tmpfile.close
      hosts = Resolv::Hosts.new(tmpfile.path)
      assert_nothing_raised(ArgumentError, bug9273) do
        hosts.each_address("") {break}
      end
    end
  end

  def test_hosts_by_command
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        hosts = Resolv::Hosts.new("|echo error")
        assert_raise(Errno::ENOENT, Errno::EINVAL) do
          hosts.each_name("") {}
        end
      end
    end
  end
end
