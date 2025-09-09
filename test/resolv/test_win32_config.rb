# frozen_string_literal: true

require 'test/unit'
require 'resolv'

class TestWin32Config < Test::Unit::TestCase
  def setup
    omit 'Win32::Resolv tests only run on Windows' unless RUBY_PLATFORM =~ /mswin|mingw|cygwin/
  end

  def test_get_item_property_string
    # Test reading a string registry value
    result = Win32::Resolv.send(:get_item_property,
                                Win32::Resolv::TCPIP_NT,
                                'DataBasePath')

    # Should return a string (empty or with a path)
    assert_instance_of String, result
  end

  def test_get_item_property_with_expand
    # Test reading an expandable string registry value
    result = Win32::Resolv.send(:get_item_property,
                                Win32::Resolv::TCPIP_NT,
                                'DataBasePath',
                                expand: true)

    # Should return a string with environment variables expanded
    assert_instance_of String, result
  end

  def test_get_item_property_dword
    # Test reading a DWORD registry value
    result = Win32::Resolv.send(:get_item_property,
                                Win32::Resolv::TCPIP_NT,
                                'UseDomainNameDevolution',
                                dword: true)

    # Should return an integer (0 or 1 typically)
    assert_kind_of Integer, result
  end

  def test_get_item_property_nonexistent_key
    # Test reading a non-existent registry key
    result = Win32::Resolv.send(:get_item_property,
                                Win32::Resolv::TCPIP_NT,
                                'NonExistentKeyThatShouldNotExist')

    # Should return empty string for non-existent string values
    assert_equal '', result
  end

  def test_get_item_property_nonexistent_key_dword
    # Test reading a non-existent registry key as DWORD
    result = Win32::Resolv.send(:get_item_property,
                                Win32::Resolv::TCPIP_NT,
                                'NonExistentKeyThatShouldNotExist',
                                dword: true)

    # Should return 0 for non-existent DWORD values
    assert_equal 0, result
  end

  def test_get_item_property_search_list
    # Test reading SearchList which may exist in the registry
    result = Win32::Resolv.send(:get_item_property,
                                Win32::Resolv::TCPIP_NT,
                                'SearchList')

    # Should return a string (may be empty if not configured)
    assert_instance_of String, result
  end

  def test_get_item_property_nv_domain
    # Test reading NV Domain which may exist in the registry
    result = Win32::Resolv.send(:get_item_property,
                                Win32::Resolv::TCPIP_NT,
                                'NV Domain')

    # Should return a string (may be empty if not configured)
    assert_instance_of String, result
  end

  def test_get_item_property_with_invalid_path
    # Test with an invalid registry path
    result = Win32::Resolv.send(:get_item_property,
                                'SYSTEM\NonExistent\Path',
                                'SomeKey')

    # Should return empty string for invalid path
    assert_equal '', result
  end

  def test_get_item_property_with_invalid_path_dword
    # Test with an invalid registry path as DWORD
    result = Win32::Resolv.send(:get_item_property,
                                'SYSTEM\NonExistent\Path',
                                'SomeKey',
                                dword: true)

    # Should return 0 for invalid path
    assert_equal 0, result
  end
end
