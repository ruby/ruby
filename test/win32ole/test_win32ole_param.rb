# frozen_string_literal: false
begin
  require 'win32ole'
rescue LoadError
end
require "test/unit"

if defined?(WIN32OLE_PARAM)
  class TestWIN32OLE_PARAM < Test::Unit::TestCase

    def setup
      ole_type = WIN32OLE_TYPE.new("Microsoft Shell Controls And Automation", "ShellLinkObject")
      m_geticonlocation = WIN32OLE_METHOD.new(ole_type, "GetIconLocation")
      @param_pbs = m_geticonlocation.params[0]

      ole_type = WIN32OLE_TYPE.new("Microsoft HTML Object Library", "FontNames")
      m_count = WIN32OLE_METHOD.new(ole_type, "Count")
      @param_p = m_count.params[0]

      ole_type = WIN32OLE_TYPE.new("Microsoft Scripting Runtime", "FileSystemObject")
      m_copyfile = WIN32OLE_METHOD.new(ole_type, "CopyFile")
      @param_source = m_copyfile.params[0]
      @param_overwritefiles = m_copyfile.params[2]

      ole_type = WIN32OLE_TYPE.new("Microsoft Scripting Runtime", "Dictionary")
      m_add = WIN32OLE_METHOD.new(ole_type, "Add")
      @param_key = m_add.params[0]
    end

    def test_s_new
      assert_raise(ArgumentError) {
        WIN32OLE_PARAM.new("hoge")
      }
      ole_type = WIN32OLE_TYPE.new("Microsoft Scripting Runtime", "FileSystemObject")
      m_copyfile = WIN32OLE_METHOD.new(ole_type, "CopyFile")
      assert_raise(IndexError) {
        WIN32OLE_PARAM.new(m_copyfile, 4);
      }
      assert_raise(IndexError) {
        WIN32OLE_PARAM.new(m_copyfile, 0);
      }
      param = WIN32OLE_PARAM.new(m_copyfile, 3)
      assert_equal("OverWriteFiles", param.name)
      assert_equal(WIN32OLE_PARAM, param.class)
      assert_equal(true, param.default)
      assert_equal("#<WIN32OLE_PARAM:OverWriteFiles=true>", param.inspect)
    end

    def test_name
      assert_equal('Source', @param_source.name)
      assert_equal('Key', @param_key.name)
    end

    def test_ole_type
      assert_equal('BSTR', @param_source.ole_type)
      assert_equal('VARIANT', @param_key.ole_type)
    end

    def test_ole_type_detail
      assert_equal(['BSTR'], @param_source.ole_type_detail)
      assert_equal(['PTR', 'VARIANT'], @param_key.ole_type_detail)
    end

    def test_input?
      assert_equal(true, @param_source.input?)
      assert_equal(false, @param_pbs.input?)
    end

    def test_output?
      assert_equal(false, @param_source.output?)
      assert_equal(true, @param_pbs.output?)
    end

    def test_optional?
      assert_equal(false, @param_source.optional?)
      assert_equal(true, @param_overwritefiles.optional?)
    end

    def test_retval?
      assert_equal(false, @param_source.retval?)
      assert_equal(true, @param_p.retval?)
    end

    def test_default
      assert_equal(nil, @param_source.default)
      assert_equal(true, @param_overwritefiles.default)
    end

    def test_to_s
      assert_equal(@param_source.name, @param_source.to_s)
    end

    def test_inspect
      assert_equal("#<WIN32OLE_PARAM:Source>", @param_source.inspect)
      assert_equal("#<WIN32OLE_PARAM:OverWriteFiles=true>", @param_overwritefiles.inspect)
    end
  end
end
