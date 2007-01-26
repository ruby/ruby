# This is test script to check WIN32OLE_VARIANT using Internet Explorer 
begin
  require 'win32ole'
rescue LoadError
end
require 'test/unit'

if defined?(WIN32OLE)
  class TestWIN32OLE_VARIANT_WITH_IE < Test::Unit::TestCase
    def create_temp_html
      fso = WIN32OLE.new('Scripting.FileSystemObject')
      dummy_file = fso.GetTempName + ".html"
      cfolder = fso.getFolder(".")
      f = cfolder.CreateTextFile(dummy_file)
      f.writeLine("<html><body>This is test HTML file for Win32OLE.</body></html>")
      f.close
      dummy_path = cfolder.path + "\\" + dummy_file
      dummy_path
    end
    def setup
      @f = create_temp_html
      @ie = WIN32OLE.new('InternetExplorer.Application')
      @ie.visible = true
      @ie.navigate("file:///#{@f}")
      while @ie.busy
        sleep 0.5
      end
    end
    def test_variant_ref_and_argv
      @ie.execWB(19, 0, nil, -1)
      size = WIN32OLE::ARGV[3]
      assert(size >= 0)

      obj = WIN32OLE_VARIANT.new(nil, WIN32OLE::VARIANT::VT_VARIANT|WIN32OLE::VARIANT::VT_BYREF)
      @ie.execWb(19, 0, nil, obj)
      assert_equal(size, obj.value)
      assert_equal(size, WIN32OLE::ARGV[3])

      obj = WIN32OLE_VARIANT.new(-1, WIN32OLE::VARIANT::VT_VARIANT|WIN32OLE::VARIANT::VT_BYREF)
      @ie.execWb(19, 0, nil, obj)
      assert_equal(size, obj.value)
      assert_equal(size, WIN32OLE::ARGV[3])
    end

    def teardown
      File.unlink(@f)
      if @ie
        @ie.quit
        @ie = nil
      end
    end
  end
end
