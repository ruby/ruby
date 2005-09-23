require 'rubyunit'
require 'win32ole'

class TestWIN32OLE_EVENT < RUNIT::TestCase
  def setup
    @excel = WIN32OLE.new("Excel.Application")
    @excel.visible = true
    @event = ""
    @event2 = ""
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

  def handler1
    @event += "handler1"
  end
  def handler2
    @event += "handler2"
  end

  def handler3
    @event += "handler3"
  end

  def test_on_event2
    book = @excel.workbooks.Add
    begin
      ev = WIN32OLE_EVENT.new(book, 'WorkbookEvents')
      ev.on_event('SheetChange'){|arg1, arg2| 
        handler1
      }
      ev.on_event('SheetChange'){|arg1, arg2| 
        handler2
      }
      book.Worksheets(1).Range("A1").value = "OK"
    ensure
      book.saved = true
    end
    assert_equal("handler2", @event)
  end

  def test_on_event3
    book = @excel.workbooks.Add
    begin
      ev = WIN32OLE_EVENT.new(book, 'WorkbookEvents')
      ev.on_event{ handler1 }
      ev.on_event{ handler2 }
      book.Worksheets(1).Range("A1").value = "OK"
    ensure
      book.saved = true
    end
    assert_equal("handler2", @event)
  end

  def test_on_event4
    book = @excel.workbooks.Add
    begin
      ev = WIN32OLE_EVENT.new(book, 'WorkbookEvents')
      ev.on_event{ handler1 }
      ev.on_event{ handler2 }
      ev.on_event('SheetChange'){|arg1, arg2| handler3 }
      book.Worksheets(1).Range("A1").value = "OK"
    ensure
      book.saved = true
    end
    assert_equal("handler3", @event)
  end

  def teardown
    @excel.quit
    @excel = nil
    GC.start
  end
end

