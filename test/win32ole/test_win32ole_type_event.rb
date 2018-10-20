# frozen_string_literal: false
begin
  require 'win32ole'
rescue LoadError
end

require 'test/unit'

if defined?(WIN32OLE_TYPE)
  require_relative 'available_ole'

  class TestWIN32OLE_TYPE_EVENT < Test::Unit::TestCase
    unless AvailableOLE.sysmon_available?
      def test_dummy_for_skip_message
        skip 'System Monitor Control is not available'
      end
    else

      def setup
        @ole_type = WIN32OLE_TYPE.new('System Monitor Control', 'SystemMonitor')
      end

      def test_implemented_ole_types
        ole_types = @ole_type.implemented_ole_types.map(&:name).sort
        assert_equal(['DISystemMonitor', 'DISystemMonitorEvents', 'ISystemMonitor'], ole_types)
      end

      def test_default_ole_types
        ole_types = @ole_type.default_ole_types.map(&:name).sort
        assert_equal(['DISystemMonitor', 'DISystemMonitorEvents'], ole_types)
      end

      def test_source_ole_types
        ole_types = @ole_type.source_ole_types.map(&:name)
        assert_equal(['DISystemMonitorEvents'], ole_types)
      end

      def test_default_event_sources
        event_sources = @ole_type.default_event_sources.map(&:name)
        assert_equal(['DISystemMonitorEvents'], event_sources)
      end
    end
  end
end
