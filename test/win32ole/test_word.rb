#
# This is test for [ruby-Bugs#3237]
#
begin
  require 'win32ole'
rescue LoadError
end
require "test/unit"

if defined?(WIN32OLE)
  class TestWIN32OLE_WITH_WORD < Test::Unit::TestCase
    
    def setup
      begin
        @obj = WIN32OLE.new('Word.Application')
      rescue WIN32OLERuntimeError
        @obj = nil
      end
    end

    def test_ole_methods
      if @obj
        @obj.visible = true
        @obj.wordbasic.disableAutoMacros(true)
        assert(true)
      end
    end

    def test_s_connect
      if @obj
        obj2 = WIN32OLE.connect("Word.Application")
        assert_instance_of(WIN32OLE, obj2)
        obj2.visible = true
      end
    end

    def teardown
      if @obj
        @obj.quit
        @obj = nil
      end
    end

  end
end
