begin
  require 'win32ole'
rescue LoadError
end

require 'test/unit'

if defined?(WIN32OLE_PARAM)
  require_relative 'available_ole'

  class TestWIN32OLE_PARAM_EVENT < Test::Unit::TestCase
    if AvailableOLE.msxml_available? || AvailableOLE.ado_available?
      def setup
        @param = AvailableOLE.event_param
      end

      def test_input?
        assert_equal(true, @param.input?)
      end

      def test_output?
        assert_equal(true, @param.output?)
      end
    else
      def test_dummy_for_skip_message
        skip 'ActiveX Data Object Library and MS XML not found'
      end
    end
  end
end
