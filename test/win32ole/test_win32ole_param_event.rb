begin
  require 'win32ole'
rescue LoadError
end

require 'test/unit'

if defined?(WIN32OLE_PARAM)

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

  class TestWIN32OLE_PARAM_EVENT < Test::Unit::TestCase
    unless ado_installed?
      def test_dummy_for_skip_message
        skip 'ActiveX Data Object Library not found'
      end
    else
      def setup
        typelib = WIN32OLE.new('ADODB.Connection').ole_typelib
        otype = WIN32OLE_TYPE.new(typelib.name, 'Connection')
        m_will_connect = WIN32OLE_METHOD.new(otype, 'WillConnect')
        @param_user_id = m_will_connect.params[0]
      end

      def test_input?
        assert_equal(true, @param_user_id.input?)
      end

      def test_output?
        assert_equal(true, @param_user_id.output?)
      end
    end
  end
end
