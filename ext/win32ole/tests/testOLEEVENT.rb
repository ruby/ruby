require 'rubyunit'
require 'win32ole'

class TestWIN32OLE_EVENT < RUNIT::TestCase
  def setup
    @excel = WIN32OLE.new("Excel.Application")
    @excel.visible = true
  end
  def test_on_event
    book = @excel.workbooks.Add
    value = ""
    begin
      ev = WIN32OLE_EVENT.new(book, 'WorkbookEvents')
      ev.on_event('SheetChange'){|arg1, arg2| 
        begin
          value = arg1.value
        rescue
          value = $!.message
        end
      }
      book.Worksheets(1).Range("A1").value = "OK"
    ensure
      book.saved = true
    end
    assert_equal("OK", value)
  end
  def teardown
    @excel.quit
    @excel = nil
    GC.start
  end
end

