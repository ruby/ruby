# You need RubyUnit and MS Excel and MSI to run this test script 

require 'rubyunit'

require 'win32ole'
require 'oleserver'

class TestOLEMETHOD < RUNIT::TestCase
  include OLESERVER
  def setup
    @excel_app = WIN32OLE_TYPE.new(MS_EXCEL_TYPELIB, 'Application')
  end
  def test_s_new
    m = WIN32OLE_METHOD.new(@excel_app, 'Quit')
    assert_instance_of(WIN32OLE_METHOD, m)
    m =  WIN32OLE_METHOD.new(@excel_app, 'WorkbookOpen')
    assert_instance_of(WIN32OLE_METHOD, m)
    m =  WIN32OLE_METHOD.new(@excel_app, 'workbookopen')
    assert_instance_of(WIN32OLE_METHOD, m)
  end
  def test_name
    m = WIN32OLE_METHOD.new(@excel_app, 'Quit')
    assert_equal('Quit', m.name)
  end
  def test_to_s
    m = WIN32OLE_METHOD.new(@excel_app, 'Quit')
    assert_equal('Quit', "#{m}")
  end
  def test_return_type
    m = WIN32OLE_METHOD.new(@excel_app, 'ActiveCell')
    assert_equal('Range', m.return_type)
    m = WIN32OLE_METHOD.new(@excel_app, 'ActivePrinter')
    assert_equal('BSTR', m.return_type)
  end
  def test_return_vtype
    m = WIN32OLE_METHOD.new(@excel_app, 'ActiveCell')
    assert_equal(WIN32OLE::VARIANT::VT_PTR, m.return_vtype)
    m = WIN32OLE_METHOD.new(@excel_app, 'ActivePrinter')
    assert_equal(WIN32OLE::VARIANT::VT_BSTR, m.return_vtype)
  end
  def test_return_type_detail
    m = WIN32OLE_METHOD.new(@excel_app, 'ActiveCell')
    assert_equal(['PTR', 'USERDEFINED', 'Range'], m.return_type_detail)
    m = WIN32OLE_METHOD.new(@excel_app, 'ActivePrinter')
    assert_equal(['BSTR'], m.return_type_detail)
  end

  def test_invoke_kind
    m = WIN32OLE_METHOD.new(@excel_app, 'ActiveCell')
    assert_equal('PROPERTYGET', m.invoke_kind)
  end
  def test_visible
    m = WIN32OLE_METHOD.new(@excel_app, 'ActiveCell')
    assert(m.visible?)
    m = WIN32OLE_METHOD.new(@excel_app, 'AddRef')
    assert(!m.visible?)
  end
  def test_event
    m =  WIN32OLE_METHOD.new(@excel_app, 'WorkbookOpen')
    assert(m.event?)
    m =  WIN32OLE_METHOD.new(@excel_app, 'ActiveCell')
    assert(!m.event?)
  end
  def test_event_interface
    m = WIN32OLE_METHOD.new(@excel_app, 'WorkbookOpen')
    assert_equal('AppEvents', m.event_interface)
    m = WIN32OLE_METHOD.new(@excel_app, 'ActiveCell')
    assert_nil(m.event_interface)
  end
  def test_helpstring
    domdoc = WIN32OLE_TYPE.new(MS_XML_TYPELIB, 'DOMDocument')
    m =  WIN32OLE_METHOD.new(domdoc, 'abort')
    assert_equal('abort an asynchronous download', m.helpstring)
  end
  def test_helpfile
    m = WIN32OLE_METHOD.new(@excel_app, 'ActiveCell')
    assert_match(/VBAXL.*\.(HLP|CHM)$/i, m.helpfile)
  end
  def test_helpcontext
    m = WIN32OLE_METHOD.new(@excel_app, 'ActiveCell')
    assert(m.helpcontext > 0)
  end
  def test_offset_vtbl
    m = WIN32OLE_METHOD.new(@excel_app, 'QueryInterface')
    assert_equal(0, m.offset_vtbl)
  end
end
