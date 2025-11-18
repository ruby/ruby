# frozen_string_literal: true

require 'test/unit'
require 'resolv'

if defined?(Win32::Resolve)
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
  end
end
