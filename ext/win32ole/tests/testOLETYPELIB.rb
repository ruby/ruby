require 'test/unit'
require 'win32ole'
require 'oleserver'

class TestOLETYPELIB < Test::Unit::TestCase
  include OLESERVER
  def test_exists_typelib
    assert(Module.constants.include?("WIN32OLE_TYPELIB"))
  end

  def test_s_new
    tlib = WIN32OLE_TYPELIB.new(MS_EXCEL_TYPELIB)
  end

  def test_s_new_non_exist_tlib
    exception_occured = false
    msg = ""
    begin
      tlib = WIN32OLE_TYPELIB.new('NON EXIST TYPELIB')
    rescue WIN32OLERuntimeError
      msg = $!.to_s
      exception_occured = true
    end
    assert_equal("not found type library `NON EXIST TYPELIB`", msg)
    assert(exception_occured)
  end

  def test_guid
    tlib = WIN32OLE_TYPELIB.new(MS_EXCEL_TYPELIB)
    assert_not_equal("",  tlib.guid)
  end

  def test_s_new_from_guid
    tlib = WIN32OLE_TYPELIB.new(MS_EXCEL_TYPELIB);
    guid = tlib.guid
    tlib2 = WIN32OLE_TYPELIB.new(guid);
    assert_equal(tlib.name, tlib2.name);
  end

  def test_version
    tlib = WIN32OLE_TYPELIB.new(MS_EXCEL_TYPELIB);
    assert(tlib.version > 0)
  end

  def test_major_version
    tlib = WIN32OLE_TYPELIB.new(MS_EXCEL_TYPELIB)
    assert(tlib.major_version > 0)
  end

  def test_minor_version
    tlib = WIN32OLE_TYPELIB.new(MS_EXCEL_TYPELIB)
    assert(tlib.minor_version >= 0)
  end

  def test_create_tlib_obj
    ex = nil
    begin
      tlib1 = WIN32OLE_TYPELIB.new(MS_EXCEL_TYPELIB)
      ex = WIN32OLE.new('Excel.Application')
      tlib2 = ex.ole_typelib
      assert_equal(tlib1.name, tlib2.name)
      assert_equal(tlib1.major_version, tlib2.major_version)
      assert_equal(tlib1.minor_version, tlib2.minor_version)
    ensure
      if ex 
        ex.quit
      end
    end
  end

  def test_create_tlib_obj2
    ex = nil
    begin
      tlib1 = WIN32OLE_TYPELIB.new(MS_EXCEL_TYPELIB)
      tlib2 = WIN32OLE_TYPELIB.new(tlib1.guid, tlib1.major_version, tlib1.minor_version)
      assert_equal(tlib1.name, tlib2.name)
      assert_equal(tlib1.major_version, tlib2.major_version)
      assert_equal(tlib1.minor_version, tlib2.minor_version)
    ensure
      if ex 
        ex.quit
      end
    end
  end

  def test_create_tlib_obj3
    ex = nil
    begin
      tlib1 = WIN32OLE_TYPELIB.new(MS_EXCEL_TYPELIB)
      tlib2 = WIN32OLE_TYPELIB.new(tlib1.guid, tlib1.version)
      assert_equal(tlib1.name, tlib2.name)
      assert_equal(tlib1.guid, tlib2.guid)
      assert_equal(tlib1.major_version, tlib2.major_version)
      assert_equal(tlib1.minor_version, tlib2.minor_version)
    ensure
      if ex 
        ex.quit
      end
    end
  end

  def test_name
    tlib = WIN32OLE_TYPELIB.new(MS_EXCEL_TYPELIB)
    assert_equal(MS_EXCEL_TYPELIB, tlib.name)
  end

  def test_to_s
    tlib = WIN32OLE_TYPELIB.new(MS_EXCEL_TYPELIB)
    assert_equal(tlib.name, tlib.to_s)
  end

  def test_path
    tlib = WIN32OLE_TYPELIB.new(MS_EXCEL_TYPELIB)
    assert(/EXCEL/ =~ tlib.path)
  end

  def test_ole_classes
    tlib = WIN32OLE_TYPELIB.new(MS_EXCEL_TYPELIB)
    classes = tlib.ole_classes
    assert(classes.instance_of?(Array))
    assert(classes.size > 0)
    assert('WIN32OLE_TYPE', classes[0].class)
    assert(classes.collect{|i| i.name}.include?('Workbooks'))
  end

  def test_s_typelibs
    tlibs = WIN32OLE_TYPELIB.typelibs
    assert(tlibs.instance_of?(Array))
    assert(tlibs.size > 0)
    assert('WIN32OLE_TYPELIB', tlibs[0].class)
    tlibnames = tlibs.collect{|i| i.name}
    tlibnames.include?('Microsoft Internet Controlls')
  end
end
