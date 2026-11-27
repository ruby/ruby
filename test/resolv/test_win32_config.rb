# frozen_string_literal: true

require 'test/unit'
require 'resolv'
require 'tempfile'

# JRuby loads its bundled win32/resolv, which lacks the registry access of the extension.
if defined?(Win32::Resolv) && Win32::Resolv.respond_to?(:tcpip_params, true)
  class TestWin32Config < Test::Unit::TestCase
    def test_get_item_property_string
      # Test reading a string registry value
      result = Win32::Resolv.send(:get_hosts_dir)

      # Should return a string (empty or with a path)
      assert_instance_of String, result
    end

    # Test reading a non-existent registry key
    def test_nonexistent_key
      assert_nil(Win32::Resolv.send(:tcpip_params) {|reg| reg.open('NonExistentKeyThatShouldNotExist')})
    end

    # Test reading a non-existent registry value
    def test_nonexistent_value
      assert_nil(Win32::Resolv.send(:tcpip_params) {|reg| reg.value('NonExistentKeyThatShouldNotExist')})
    end

    def test_default_config_hash_with_resolv_conf
      Tempfile.create("resolv.conf") do |f|
        f.puts "nameserver 192.0.2.1"
        f.close
        nameserver = Resolv::DNS::Config.default_config_hash(f.path)[:nameserver]
        if /cygwin/ =~ RUBY_PLATFORM
          assert_equal(["192.0.2.1"], nameserver)
        else
          assert_not_include(Array(nameserver), "192.0.2.1")
        end
      end
    end
  end
end
