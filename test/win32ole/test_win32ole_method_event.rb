begin
  require 'win32ole'
rescue LoadError
end

require 'test/unit'

if defined?(WIN32OLE_METHOD)

  def ado_installed?
    installed = false
    if defined?(WIN32OLE)
      begin
        WIN32OLE.new('ADODB.Connection')
        installed = true
      rescue
      end
    end
    installed
  end

  class TestWIN32OLE_METHOD_EVENT < Test::Unit::TestCase
    unless ado_installed?
      def test_dummy_for_skip_message
        skip 'ActiveX Data Object Library not found'
      end
    else
      def setup
        typelib = WIN32OLE.new('ADODB.Connection').ole_typelib
        otype = WIN32OLE_TYPE.new(typelib.name, 'Connection')
        @will_connect = WIN32OLE_METHOD.new(otype, 'WillConnect')
        ole_type = WIN32OLE_TYPE.new('Microsoft Shell Controls And Automation', 'Shell')
        @namespace = WIN32OLE_METHOD.new(ole_type, 'namespace')
      end

      def test_event?
        assert(@will_connect.event?)
      end

      def test_event_interface
        assert('ConnectionEvents', @will_connect.event_interface)
      end

      def test_event_interface_is_nil
        assert_equal(nil, @namespace.event_interface)
      end
    end
  end
end
