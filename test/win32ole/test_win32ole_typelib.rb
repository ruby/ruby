begin
  require 'win32ole'
rescue LoadError
end

require "test/unit"

if defined?(WIN32OLE_TYPELIB)
  class TestWIN32OLE_TYPELIB < Test::Unit::TestCase
    def test_s_typelibs
      tlibs = WIN32OLE_TYPELIB.typelibs
      assert_instance_of(Array, tlibs)
      assert(tlibs.size > 0)
      tlib = tlibs.find {|tlib| tlib.name == "Microsoft Shell Controls And Automation"}
      assert(tlib)
    end

    def test_initialize
      assert_raise(ArgumentError) {
        WIN32OLE_TYPELIB.new(1,2,3,4)
      }
      tlib = WIN32OLE_TYPELIB.new("Microsoft Shell Controls And Automation")
      assert_instance_of(WIN32OLE_TYPELIB, tlib)

      tlib = WIN32OLE_TYPELIB.new("Microsoft Shell Controls And Automation", 1.0)
      assert_instance_of(WIN32OLE_TYPELIB, tlib)

      tlib = WIN32OLE_TYPELIB.new("Microsoft Shell Controls And Automation", 1, 0)
      assert_instance_of(WIN32OLE_TYPELIB, tlib)
      guid = tlib.guid

      tlib_by_guid = WIN32OLE_TYPELIB.new(guid, 1, 0)
      assert_instance_of(WIN32OLE_TYPELIB, tlib_by_guid)
      assert_equal("Microsoft Shell Controls And Automation" , tlib_by_guid.name)

      assert_raise(WIN32OLERuntimeError) {
        WIN32OLE_TYPELIB.new("Non Exist Type Library")
      }
    end

    def test_guid
      tlib = WIN32OLE_TYPELIB.new("Microsoft Shell Controls And Automation")
      assert_equal("{50A7E9B0-70EF-11D1-B75A-00A0C90564FE}", tlib.guid)
    end

    def test_name
      tlib = WIN32OLE_TYPELIB.new("Microsoft Shell Controls And Automation")
      assert_equal("Microsoft Shell Controls And Automation", tlib.name)
      tlib = WIN32OLE_TYPELIB.new("{50A7E9B0-70EF-11D1-B75A-00A0C90564FE}")
      assert_equal("Microsoft Shell Controls And Automation", tlib.name)
    end

    def test_version
      tlib = WIN32OLE_TYPELIB.new("Microsoft Shell Controls And Automation")
      assert_equal(1.0, tlib.version)
    end

    def test_major_version
      tlib = WIN32OLE_TYPELIB.new("Microsoft Shell Controls And Automation")
      assert_equal(1, tlib.major_version)
    end

    def test_minor_version
      tlib = WIN32OLE_TYPELIB.new("Microsoft Shell Controls And Automation")
      assert_equal(0, tlib.minor_version)
    end

    def test_path
      tlib = WIN32OLE_TYPELIB.new("Microsoft Shell Controls And Automation")
      assert_match(/shell32\.dll$/i, tlib.path)
    end

    def test_to_s
      tlib = WIN32OLE_TYPELIB.new("Microsoft Shell Controls And Automation")
      assert_equal("Microsoft Shell Controls And Automation", tlib.to_s)
    end

    def test_ole_classes
      tlib = WIN32OLE_TYPELIB.new("Microsoft Shell Controls And Automation")
      ole_classes = tlib.ole_classes
      assert_instance_of(Array, ole_classes)
      assert(ole_classes.size > 0)
      assert_instance_of(WIN32OLE_TYPE, ole_classes[0])
    end

    def test_inspect
      tlib = WIN32OLE_TYPELIB.new("Microsoft Shell Controls And Automation")
      assert_equal("#<WIN32OLE_TYPELIB:Microsoft Shell Controls And Automation>", tlib.inspect)
    end

  end
end
