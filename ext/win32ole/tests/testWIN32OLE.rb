# You need RubyUnit and MS Excel and MSI to run this test script 

require 'test/unit'
require 'runit/testcase'
# require 'runit/cui/testrunner'

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

  def test_convert_bignum
    book = @excel.workbooks.add
    sheet = book.worksheets(1)
    begin
      sheet.range("A1").value = 999999999
      sheet.range("A2").value = 9999999999
      sheet.range("A3").value = "=A1*10 + 9"
      assert_equal(9999999999, sheet.range("A2").value)
      assert_equal(9999999999, sheet.range("A3").value)
     
    ensure
      book.saved = true
    end
  end


  def teardown
    @excel.quit
    @excel = nil
    GC.start
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
end
