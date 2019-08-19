begin
  require 'win32ole'
rescue LoadError
end

require 'test/unit'

if defined?(WIN32OLE_METHOD)
  require_relative 'available_ole'
  class TestWIN32OLE_METHOD_EVENT < Test::Unit::TestCase
    unless AvailableOLE.sysmon_available?
      def test_dummy_for_skip_message
        skip 'System Monitor Control is not available'
      end
    else
      def setup
        ole_type = WIN32OLE_TYPE.new('System Monitor Control', 'SystemMonitor')
        @on_dbl_click = WIN32OLE_METHOD.new(ole_type, 'OnDblClick')
        ole_type = WIN32OLE_TYPE.new('Microsoft Shell Controls And Automation', 'Shell')
        @namespace = WIN32OLE_METHOD.new(ole_type, 'namespace')
      end

      def test_event?
        assert(@on_dbl_click.event?)
      end

      def test_event_interface
        assert('DISystemMonitorEvents', @on_dbl_click.event_interface)
      end

      def test_event_interface_is_nil
        assert_equal(nil, @namespace.event_interface)
      end
    end
  end
end
