require_relative 'base'

class TestMkmf
  class TestHaveFramework < TestMkmf
    def test_cocoa_framework
      assert(have_framework("Cocoa"), "try as Objective-C")
    end
  end
end if /darwin/ =~ RUBY_PLATFORM
