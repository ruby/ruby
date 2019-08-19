# frozen_string_literal: true
begin
  require_relative 'helper'
rescue LoadError
end

class TestFiddle < Fiddle::TestCase
  def test_windows_constant
    require 'rbconfig'
    if RbConfig::CONFIG['host_os'] =~ /mswin|mingw/
      assert Fiddle::WINDOWS, "Fiddle::WINDOWS should be 'true' on Windows platforms"
    else
      refute Fiddle::WINDOWS, "Fiddle::WINDOWS should be 'false' on non-Windows platforms"
    end
  end

end if defined?(Fiddle)
