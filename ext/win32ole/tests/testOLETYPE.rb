# You need RubyUnit and MS Excel and MSI to run this test script

require 'rubyunit'

require 'win32ole'
require 'oleserver'

class TestOLETYPE < RUNIT::TestCase
  include OLESERVER
  def test_s_new
    type = WIN32OLE_TYPE.new(MS_EXCEL_TYPELIB, 'Application')
    assert_instance_of(WIN32OLE_TYPE, type)
  end
  def test_s_ole_classes
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    assert(classes.size > 0)
  end
  def test_s_typelibs
    libs = WIN32OLE_TYPE.typelibs
    assert(libs.include?(MS_EXCEL_TYPELIB))
    assert(libs.include?(MS_XML_TYPELIB))
  end
  def test_s_progids
    progids = WIN32OLE_TYPE.progids
    assert(progids.include?('Excel.Application'))
  end
  def test_name
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    class_names = classes.collect{|c|
      c.name
    }
    assert(class_names.include?('Application'))
  end

  def test_class_to_s
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    class_names = classes.collect{|c|
      "#{c}"
    }
    assert(class_names.include?('Application'))
  end

  def test_ole_type
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    app = classes.find {|c| c.name == 'Application'}
    assert_equal('Class', app.ole_type)
    app = classes.find {|c| c.name == '_Application'}
    assert_equal('Dispatch', app.ole_type)
  end
  def test_typekind
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    app = classes.find {|c| c.name == 'Application'}
    assert_equal(5, app.typekind)
  end
  def test_visible
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    app = classes.find {|c| c.name == 'Application'}
    assert(app.visible?)
    app = classes.find {|c| c.name == 'IAppEvents'}
    assert(!app.visible?)
  end
  def test_src_type
    classes = WIN32OLE_TYPE.ole_classes(MS_XML_TYPELIB)
    domnode = classes.find {|c| c.name == 'DOMNodeType'}
    assert_equal('tagDOMNodeType', domnode.src_type)
  end
  def test_helpstring
    classes = WIN32OLE_TYPE.ole_classes(MS_XML_TYPELIB)
    domdoc = classes.find {|c| c.name == 'DOMDocument'}
    assert_equal('W3C-DOM XML Document', domdoc.helpstring)
  end
  def test_variables
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    xlchart = classes.find {|c| c.name == 'XlChartType'}
    assert(xlchart.variables.size > 0)
  end
  def test_ole_methods
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    worksheet = classes.find {|c| c.name == 'Worksheet'}
    assert(worksheet.ole_methods.size > 0)
  end
  def test_helpfile
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    worksheet = classes.find {|c| c.name == 'Worksheet'}
    assert_match(/VBAXL.*\.(CHM|HLP)$/, worksheet.helpfile)
  end
  def test_helpcontext
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    worksheet = classes.find {|c| c.name == 'Worksheet'}
    assert_equal(131088, worksheet.helpcontext)
  end
  def test_to_s
    type = WIN32OLE_TYPE.new(MS_EXCEL_TYPELIB, 'Application')
    assert_equal("Application", "#{type}");
  end
end
