# You need RubyUnit and MS Excel and MSI to run this test script 

require 'runit/testcase'
require 'runit/cui/testrunner'

require 'win32ole'
require 'oleserver'

module EXCEL_CONST
end

module CONST1
end

module CONST2
end

module CONST3
end

class TestWin32OLE < RUNIT::TestCase
  include OLESERVER
  def setup
    @excel = WIN32OLE.new("Excel.Application")
    @excel.visible = true
  end
  def test_s_new
    assert_instance_of(WIN32OLE, @excel)
  end
  def test_s_new_DCOM
    rexcel = WIN32OLE.new("Excel.Application", "localhost")
    assert_instance_of(WIN32OLE, rexcel)
    rexcel.visible = true
    rexcel.quit
  end
  def test_s_new_from_clsid
    excel = WIN32OLE.new("{00024500-0000-0000-C000-000000000046}")
    assert_instance_of(WIN32OLE, excel)
    excel.quit
    exc = assert_exception(WIN32OLERuntimeError) {
      WIN32OLE.new("{000}")
    }
    assert_match(/unknown OLE server: `\{000\}'/, exc.message)
  end
  def test_s_connect
    excel2 = WIN32OLE.connect('Excel.Application')
    assert_instance_of(WIN32OLE, excel2)
  end

  def test_s_const_load
    assert(!defined?(EXCEL_CONST::XlTop))
    WIN32OLE.const_load(@excel, EXCEL_CONST)
    assert_equal(-4160, EXCEL_CONST::XlTop)

    assert(!defined?(CONST1::XlTop))
    WIN32OLE.const_load(MS_EXCEL_TYPELIB, CONST1)
    assert_equal(-4160, CONST1::XlTop)
  end

  def test_s_codepage
    assert_equal(WIN32OLE::CP_ACP, WIN32OLE.codepage)
  end

  def test_s_codepage_set
    WIN32OLE.codepage = WIN32OLE::CP_UTF8
    assert_equal(WIN32OLE::CP_UTF8, WIN32OLE.codepage)
    WIN32OLE.codepage = WIN32OLE::CP_ACP
  end

  def test_const_CP_ACP
    assert_equal(0, WIN32OLE::CP_ACP)
  end

  def test_const_CP_OEMCP
    assert_equal(1, WIN32OLE::CP_OEMCP)
  end

  def test_const_CP_MACCP
    assert_equal(2, WIN32OLE::CP_MACCP)
  end

  def test_const_CP_THREAD_ACP
    assert_equal(3, WIN32OLE::CP_THREAD_ACP)
  end

  def test_const_CP_SYMBOL
    assert_equal(42, WIN32OLE::CP_SYMBOL)
  end

  def test_const_CP_UTF7
    assert_equal(65000, WIN32OLE::CP_UTF7)
  end

  def test_const_CP_UTF8
    assert_equal(65001, WIN32OLE::CP_UTF8)
  end

  def test_s_codepage_changed
    book = @excel.workbooks.add
    sheet = book.worksheets(1)
    begin
      WIN32OLE.codepage = WIN32OLE::CP_UTF8
      sheet.range("A1").value = [0x3042].pack("U*")
      val = sheet.range("A1").value
      assert_equal("\343\201\202", val)
      WIN32OLE.codepage = WIN32OLE::CP_ACP
      val = sheet.range("A1").value
      assert_equal("\202\240", val)
    ensure
      book.saved = true
    end
  end

  def test_get_win32ole_object
    workbooks = @excel.Workbooks;
    assert_instance_of(WIN32OLE, workbooks)
  end
  def test_each
    workbooks = @excel.Workbooks
    assert_no_exception {
      i = 0;
      workbooks.each do |workbook|
        print i += 1
      end
    }
    workbooks.add
    workbooks.add
    i = 0
    workbooks.each do |workbook|
      i+=1
    end
    assert_equal(2, i)
    workbooks.each do |workbook|
      workbook.saved = true
    end
  end
  def test_setproperty_bracket
    book = @excel.workbooks.add
    sheet = book.worksheets(1)
    begin
      sheet.range("A1")['Value'] = 10
      assert_equal(10, sheet.range("A1").value)
      sheet['Cells', 1, 2] = 10
      assert_equal(10, sheet.range("B1").value)
      assert_equal(10, sheet['Cells', 1, 2].value)
    ensure
      book.saved = true
    end
  end
  def test_convert_bignum
    book = @excel.workbooks.add
    sheet = book.worksheets(1)
    begin
      sheet.range("A1").value = 999999999
      sheet.range("A2").value = 9999999999
      sheet.range("A3").value = "=A1*10 + 9"
      assert_equal(9999999999, sheet.range("A2").value)
      assert_equal(9999999999, sheet.range("A3").value)
      sheet.range("A4").value = "2008/03/04"
      assert_equal("2008/03/04 00:00:00", sheet.range("A4").value)
    ensure
      book.saved = true
    end
  end

  def test_ole_invoke_with_named_arg
    book = @excel.workbooks.add
    sheets = book.worksheets
    sheet = book.worksheets(1)
    num = sheets.count
    begin
      sheets.add({'count' => 2, 'after'=>sheet})
      assert_equal(2, sheets.count - num);
    ensure
      book.saved = true
    end
  end

  def test_ole_invoke_with_named_arg_last
    book = @excel.workbooks.add
    sheets = book.worksheets
    sheet = book.worksheets(1)
    num = sheets.count
    begin
      sheets.add(sheet, {'count' => 2})
      assert_equal(2, sheets.count - num);
    ensure
      book.saved = true
    end
  end

  def test_setproperty
    @excel.setproperty('Visible', false)
    assert_equal(false, @excel.Visible)
    @excel.setproperty('Visible', true)
    assert_equal(true, @excel.Visible)
    book = @excel.workbooks.add
    sheet = book.worksheets(1)
    begin
      sheet.setproperty('Cells', 1, 2, 10)
      assert_equal(10, sheet.range("B1").value)
    ensure
      book.saved = true
    end
  end
  def test_no_exist_property
    isok = false
    begin
      @excel.unknown_prop = 1
    rescue WIN32OLERuntimeError
      isok = true
    end
    assert(isok)

    isok = false
    begin
      @excel['unknown_prop'] = 2
    rescue WIN32OLERuntimeError
      isok = true
    end
    assert(isok)
  end

  def test_setproperty_with_equal
    book = @excel.workbooks.add
    sheet = book.worksheets(1)
    begin
      sheet.range("B1").value = 10
      assert_equal(10, sheet.range("B1").value)
      sheet.range("C1:D1").value = [11, 12]
      assert_equal(11, sheet.range("C1").value)
      assert_equal(12, sheet.range("D1").value)
    ensure
      book.saved = true
    end
  end
  def test_invoke
    workbooks = @excel.invoke( 'workbooks' )
    assert_instance_of(WIN32OLE, workbooks)
    book = workbooks.invoke( 'add' )
    assert_instance_of(WIN32OLE, book)
  end
  def test_ole_methods
    methods = @excel.ole_methods
    method_names = methods.collect{|m| m.name}
    assert(method_names.include?("Quit"))
  end
  def test_ole_func_methods
    methods = @excel.ole_func_methods
    assert(methods.size > 0)
    method_names = methods.collect{|m| m.name}
    assert(method_names.include?("Quit"))
  end
  def test_ole_put_methods
    methods = @excel.ole_put_methods
    assert(methods.size > 0)
    method_names = methods.collect{|m| m.name}
    assert(method_names.include?("Visible"))
  end
  def test_ole_get_methods
    methods = @excel.ole_get_methods
    assert(methods.size > 0)
    method_names = methods.collect{|m| m.name}
    assert(method_names.include?("Visible"))
  end
  def test_ole_method_help
    quit_info = @excel.ole_method_help("Quit")
    assert_equal(0, quit_info.size_params)
    assert_equal(0, quit_info.size_opt_params)

    workbooks = @excel.Workbooks
    add_info = workbooks.ole_method_help("Add")
    assert_equal(1, add_info.size_params)
    assert_equal(1, add_info.size_opt_params)
    assert(add_info.params[0].input?)
    assert(add_info.params[0].optional?)
    assert_equal('VARIANT', add_info.params[0].ole_type)
  end
  def teardown
    @excel.quit
    @excel = nil
    GC.start
  end
end

class TestWin32OLE_WITH_MSI < RUNIT::TestCase
  def setup
    installer = WIN32OLE.new("WindowsInstaller.Installer")
    @record = installer.CreateRecord(2)
  end

  # Sorry, this test fails. 
  # Win32OLE does not support this style to set property.
  # Use Win32OLE#setproperty or Win32OLE#[]= .
  # def test_invoke
  #   @record.invoke("StringData", 1, 'cccc')
  #   assert_equal('cccc', @record.StringData(1))
  # end

  def test_setproperty
    @record.setproperty( "StringData", 1, 'dddd')
    assert_equal('dddd', @record.StringData(1))
  end
  def test_bracket_equal_with_arg
    @record[ "StringData", 1 ] =  'ffff'
    assert_equal('ffff', @record.StringData(1))
  end

  def test__invoke
    shell=WIN32OLE.new('Shell.Application')
    assert_equal(shell.NameSpace(0).title, shell._invoke(0x60020002, [0], [WIN32OLE::VARIANT::VT_VARIANT]).title)
  end
end

# ---------------------
#
# a subclass of Win32OLE
# override new() and connect()
class MyExcel<WIN32OLE
    def MyExcel.new 
        super "Excel.Application"
    end
    def MyExcel.connect
        super "Excel.Application"
    end
end

class TestMyExcel < TestWin32OLE
#
# because we overrided new() and connect()
# we need to change the test.
# also, because the class will be different
# 
  def setup
    @excel = MyExcel.new
    @excel.visible = true
  end
  def test_s_new
    assert_instance_of(MyExcel, @excel)
  end
  def test_s_connect
    excel2 = MyExcel.connect
    assert_instance_of(MyExcel, excel2)
  end
#
# const_load didn't like to be called twice,
# and I don't know how to undefine something in Ruby yet 
# so, hide the test.
#
  private :test_s_const_load
end

if $0 == __FILE__
  puts "Now Test Win32OLE version #{WIN32OLE::VERSION}"
  if ARGV.size == 0
	suite = RUNIT::TestSuite.new
	suite.add_test(TestWin32OLE.suite)
	suite.add_test(TestMyExcel.suite)
    begin
      installer = WIN32OLE.new("WindowsInstaller.Installer")
      suite.add_test(TestWin32OLE_WITH_MSI.suite)
    rescue
      puts "Skip some test with MSI"
    end
  else
    suite = RUNIT::TestSuite.new
    ARGV.each do |testmethod|
      suite.add_test(TestWin32OLE.new(testmethod))
    end
  end
  RUNIT::CUI::TestRunner.quiet_mode = true
  RUNIT::CUI::TestRunner.run(suite)
end
