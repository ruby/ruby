require_relative 'base'

class TestMkmf
  class TestHaveFramework < TestMkmf
    def test_core_foundation_framework
      assert(have_framework("CoreFoundation"), mkmflog("try as Objective-C"))
    end

    def test_multi_frameworks
      assert(have_framework("CoreFoundation"), mkmflog("try as Objective-C"))
      assert(have_framework("Cocoa"), mkmflog("try as Objective-C"))
    end
  end
end if /darwin/ =~ RUBY_PLATFORM
