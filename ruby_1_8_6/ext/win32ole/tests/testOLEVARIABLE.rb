# You need RubyUnit and MS Excel and MSI to run this test script 

require 'rubyunit'

require 'win32ole'
require 'oleserver'

class TestOLEVARIABLE < RUNIT::TestCase
  include OLESERVER
  def test_name
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    chart = classes.find {|c| c.name == 'XlChartType'}
    var_names = chart.variables.collect {|m| m.name}
    assert(var_names.size > 0)
    assert(var_names.include?('xl3DColumn'))
  end
  def test_to_s
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    chart = classes.find {|c| c.name == 'XlChartType'}
    var_names = chart.variables.collect {|m| "#{m}"}
    assert(var_names.size > 0)
    assert(var_names.include?('xl3DColumn'))
  end
  def test_ole_type
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    chart = classes.find {|c| c.name == 'XlChartType'}
    var = chart.variables.find {|m| m.name == 'xl3DColumn'}
    assert_equal('INT', var.ole_type)
  end
  def test_ole_type_detail
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    chart = classes.find {|c| c.name == 'XlChartType'}
    var = chart.variables.find {|m| m.name == 'xl3DColumn'}
    assert_equal(['INT'], var.ole_type_detail)
  end

  def test_value
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    chart = classes.find {|c| c.name == 'XlChartType'}
    var = chart.variables.find {|m| m.name == 'xl3DColumn'}
    assert_equal(-4100, var.value)
  end
  def test_visible
    classes = WIN32OLE_TYPE.ole_classes(MS_EXCEL_TYPELIB)
    chart = classes.find {|c| c.name == 'XlChartType'}
    var = chart.variables.find {|m| m.name == 'xl3DColumn'}
    assert(var.visible?)
  end
end
