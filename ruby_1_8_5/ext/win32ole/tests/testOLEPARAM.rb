# You need RubyUnit and MS Excel and MSI to run this test script 

require 'rubyunit'

require 'win32ole'
require 'oleserver'

class TestOLEPARAM < RUNIT::TestCase
  include OLESERVER
  def test_name
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    sh = classes.find {|c| c.name == 'Worksheet'}
    saveas = sh.ole_methods.find {|m| m.name == 'SaveAs'}
    param_names = saveas.params.collect{|p| p.name}
    assert(param_names.size > 0)
    assert(param_names.include?('Filename'))
  end
  def test_to_s
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    sh = classes.find {|c| c.name == 'Worksheet'}
    saveas = sh.ole_methods.find {|m| m.name == 'SaveAs'}
    param_names = saveas.params.collect{|p| "#{p}"}
    assert(param_names.include?('Filename'))
  end
  def test_ole_type
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    methods = classes.find {|c| c.name == 'Worksheet'}.ole_methods
    f = methods.find {|m| m.name == 'SaveAs'}
    assert_equal('BSTR', f.params[0].ole_type)
    methods = classes.find {|c| c.name == 'Workbook'}.ole_methods
    f = methods.find {|m| m.name == 'SaveAs'}
    assert_equal('XlSaveAsAccessMode', f.params[6].ole_type)
  end
  def test_ole_type_detail
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    methods = classes.find {|c| c.name == 'Worksheet'}.ole_methods
    f = methods.find {|m| m.name == 'SaveAs'}
    assert_equal(['BSTR'], f.params[0].ole_type_detail)
    methods = classes.find {|c| c.name == 'Workbook'}.ole_methods
    f = methods.find {|m| m.name == 'SaveAs'}
    assert_equal(['USERDEFINED', 'XlSaveAsAccessMode'], f.params[6].ole_type_detail)
  end
  def test_input
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    methods = classes.find {|c| c.name == 'Worksheet'}.ole_methods
    f = methods.find {|m| m.name == 'SaveAs'}
    assert(f.params[0].input?)
  end
  
  def test_output
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    methods = classes.find {|c| c.name == 'Worksheet'}.ole_methods
    f = methods.find {|m| m.name == 'SaveAs'}
    assert(!f.params[0].output?)
  end
  def test_optional
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    methods = classes.find {|c| c.name == 'Worksheet'}.ole_methods
    f = methods.find {|m| m.name == 'SaveAs'}
    assert(!f.params[0].optional?)
    methods = classes.find {|c| c.name == 'Workbook'}.ole_methods
    f = methods.find {|m| m.name == 'SaveAs'}
    assert(f.params[0].optional?)
  end
end
