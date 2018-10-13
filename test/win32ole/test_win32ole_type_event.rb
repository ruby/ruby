# frozen_string_literal: false
begin
  require 'win32ole'
rescue LoadError
end
require "test/unit"

if defined?(WIN32OLE_TYPE)
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

  class TestWIN32OLE_TYPE_EVENT < Test::Unit::TestCase
    unless ado_installed?
      def test_dummy_for_skip_message
        skip 'ActiveX Data Object Library not found'
      end
    else

      def setup
        typelib = WIN32OLE.new('ADODB.Connection').ole_typelib
        @ole_type = WIN32OLE_TYPE.new(typelib.name, 'Connection')
      end

      def test_implemented_ole_types
        ole_types = @ole_type.implemented_ole_types.map(&:name).sort
        assert_equal(['ConnectionEvents', '_Connection'], ole_types)
      end

      def test_default_ole_types
        ole_types = @ole_type.default_ole_types.map(&:name).sort
        assert_equal(['ConnectionEvents', '_Connection'], ole_types)
      end

      def test_source_ole_types
        ole_types = @ole_type.source_ole_types.map(&:name)
        assert_equal(['ConnectionEvents'], ole_types)
      end

      def test_default_event_sources
        event_sources = @ole_type.default_event_sources.map(&:name)
        assert_equal(['ConnectionEvents'], event_sources)
      end
    end
  end
end
