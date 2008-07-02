begin
  require 'win32ole'
rescue LoadError
end
require 'test/unit'

if defined?(WIN32OLE_EVENT)
  class TestWIN32OLE_EVENT < Test::Unit::TestCase
    def create_temp_html
      fso = WIN32OLE.new('Scripting.FileSystemObject')
      dummy_file = fso.GetTempName + ".html"
      cfolder = fso.getFolder(".")
      f = cfolder.CreateTextFile(dummy_file)
      f.writeLine("<html><body>This is test HTML file for Win32OLE.</body></html>")
      f.close
      dummy_path = cfolder.path + "\\" + dummy_file
      dummy_path
    end

    def setup
      @ie = WIN32OLE.new("InternetExplorer.Application")
      @ie.visible = true
      @event = ""
      @event2 = ""
      @event3 = ""
      @f = create_temp_html
    end

    def default_handler(event, *args)
      @event += event
    end

    def test_on_event
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event {|*args| default_handler(*args)}
      @ie.navigate("file:///#{@f}")
      while @ie.busy
        WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents') 
        GC.start  
        sleep 0.1
      end
      assert_match(/BeforeNavigate/, @event)
      assert_match(/NavigateComplete/, @event)
    end

    def test_on_event2
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event('BeforeNavigate') {|*args| handler1}
      ev.on_event('BeforeNavigate') {|*args| handler2}
      @ie.navigate("file:///#{@f}")
      while @ie.busy
        sleep 0.1
      end
      assert_equal("handler2", @event2)
    end

    def test_on_event3
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event {|*args| handler1}
      ev.on_event {|*args| handler2}
      @ie.navigate("file:///#{@f}")
      while @ie.busy
        sleep 0.1
      end
      assert_equal("handler2", @event2)
    end

    def test_on_event4
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event{|*args| handler1}
      ev.on_event{|*args| handler2}
      ev.on_event('NavigateComplete'){|*args| handler3(*args)}
      @ie.navigate("file:///#{@f}")
      while @ie.busy
        sleep 0.1
      end
      assert(@event3!="")
      assert("handler2", @event2)
    end

    def test_on_event5
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event {|*args| default_handler(*args)}
      ev.on_event('NavigateComplete'){|*args| handler3(*args)}
      @ie.navigate("file:///#{@f}")
      while @ie.busy
        sleep 0.1
      end
      assert_match(/BeforeNavigate/, @event)
      assert(/NavigateComplete/ !~ @event)
      assert(@event!="")
    end

    def test_unadvise
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event {|*args| default_handler(*args)}
      @ie.navigate("file:///#{@f}")
      while @ie.busy
        sleep 0.1
      end
      assert_match(/BeforeNavigate/, @event)
      ev.unadvise
      @event = ""
      @ie.navigate("file:///#{@f}")
      while @ie.busy
        sleep 0.1
      end
      assert_equal("", @event);
      assert_raise(WIN32OLERuntimeError) {
        ev.on_event {|*args| default_handler(*args)}
      }
    end

    def handler1
      @event2 = "handler1"
    end

    def handler2
      @event2 = "handler2"
    end

    def handler3(url)
      @event3 += url
    end

    def teardown
      @ie.quit
      @ie = nil
      File.unlink(@f)
      GC.start
    end
  end
end
