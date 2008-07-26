begin
  require 'win32ole'
rescue LoadError
end
require 'test/unit'

if defined?(WIN32OLE_EVENT)
  class TestWIN32OLE_EVENT < Test::Unit::TestCase
    module IE
    end
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

    def message_loop
      WIN32OLE_EVENT.message_loop
      sleep 0.1
    end

    def wait_ie
      while @ie.readyState != IE::READYSTATE_COMPLETE
        message_loop
      end
    end

    def setup
      WIN32OLE_EVENT.message_loop
      @ie = WIN32OLE.new("InternetExplorer.Application")
      if !defined?(IE::READYSTATE_COMPLETE)
        WIN32OLE.const_load(@ie, IE)
      end
      @ie.visible = true
      message_loop
      @event = ""
      @event2 = ""
      @event3 = ""
      @f = create_temp_html
    end

    def default_handler(event, *args)
      @event += event
    end

    def test_s_new
      assert_raise(TypeError) {
        ev = WIN32OLE_EVENT.new("A")
      }
    end

    def test_s_new_without_itf
      ev = WIN32OLE_EVENT.new(@ie)
      ev.on_event {|*args| default_handler(*args)}
      @ie.navigate("file:///#{@f}")
      while @ie.busy
        WIN32OLE_EVENT.new(@ie)
        GC.start  
        message_loop
      end
      assert_match(/BeforeNavigate/, @event)
      assert_match(/NavigateComplete/, @event)
    end

    def test_on_event
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event {|*args| default_handler(*args)}
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_match(/BeforeNavigate/, @event)
      assert_match(/NavigateComplete/, @event)
    end

    def test_on_event2
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event('BeforeNavigate') {|*args| handler1}
      ev.on_event('BeforeNavigate') {|*args| handler2}
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_equal("handler2", @event2)
    end

    def test_on_event3
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event {|*args| handler1}
      ev.on_event {|*args| handler2}
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_equal("handler2", @event2)
    end

    def test_on_event4
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event{|*args| handler1}
      ev.on_event{|*args| handler2}
      ev.on_event('NavigateComplete'){|*args| handler3(*args)}
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert(@event3!="")
      assert("handler2", @event2)
    end

    def test_on_event5
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event {|*args| default_handler(*args)}
      ev.on_event('NavigateComplete'){|*args| handler3(*args)}
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_match(/BeforeNavigate/, @event)
      assert(/NavigateComplete/ !~ @event)
      assert(@event!="")
    end

    def test_unadvise
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event {|*args| default_handler(*args)}
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_match(/BeforeNavigate/, @event)
      ev.unadvise
      @event = ""
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_equal("", @event);
      assert_raise(WIN32OLERuntimeError) {
        ev.on_event {|*args| default_handler(*args)}
      }
    end

    def test_non_exist_event
      assert_raise(RuntimeError) {
        ev = WIN32OLE_EVENT.new(@ie, 'XXXX')
      }
      dict = WIN32OLE.new('Scripting.Dictionary')
      assert_raise(RuntimeError) {
        ev = WIN32OLE_EVENT.new(dict)
      }
    end

    def test_on_event_with_outargs
      ev = WIN32OLE_EVENT.new(@ie)
      # ev.on_event_with_outargs('BeforeNavigate'){|*args|
      #  args.last[5] = true # Cancel = true
      # }
      ev.on_event_with_outargs('BeforeNavigate2'){|*args|
        args.last[6] = true # Cancel = true
      }
      bl = @ie.locationURL
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_equal(bl, @ie.locationURL)
    end

    def test_on_event_hash_return
      ev = WIN32OLE_EVENT.new(@ie)
      ev.on_event('BeforeNavigate2'){|*args|
        {:return => 1, :Cancel => true}
      }
      bl = @ie.locationURL
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_equal(bl, @ie.locationURL)
    end

    def test_on_event_hash_return2
      ev = WIN32OLE_EVENT.new(@ie)
      ev.on_event('BeforeNavigate2'){|*args|
        {:Cancel => true}
      }
      bl = @ie.locationURL
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_equal(bl, @ie.locationURL)
    end

    def test_on_event_hash_return3
      ev = WIN32OLE_EVENT.new(@ie)
      ev.on_event('BeforeNavigate2'){|*args|
        {'Cancel' => true}
      }
      bl = @ie.locationURL
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_equal(bl, @ie.locationURL)
    end
    
    def test_on_event_hash_return4
      ev = WIN32OLE_EVENT.new(@ie)
      ev.on_event('BeforeNavigate2'){|*args|
        {'return' => 2, 'Cancel' => true}
      }
      bl = @ie.locationURL
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_equal(bl, @ie.locationURL)
    end

    def test_on_event_hash_return5
      ev = WIN32OLE_EVENT.new(@ie)
      ev.on_event('BeforeNavigate2'){|*args|
        {6 => true}
      }
      bl = @ie.locationURL
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_equal(bl, @ie.locationURL)
    end

    def test_off_event
      ev = WIN32OLE_EVENT.new(@ie)
      ev.on_event{handler1}
      ev.off_event
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_equal("", @event2)
    end

    def test_off_event_arg
      ev = WIN32OLE_EVENT.new(@ie)
      ev.on_event('BeforeNavigate2'){handler1}
      ev.off_event('BeforeNavigate2')
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert_equal("", @event2)
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
      message_loop
      @ie = nil
      i = 0
      begin 
        i += 1
        File.unlink(@f) if i < 10
      rescue Errno::EACCES
        message_loop
        retry
      end
      message_loop
      GC.start
      message_loop
    end

    class Handler1
      attr_reader :val1, :val2, :val3, :val4
      def initialize
        @val1 = nil
        @val2 = nil
        @val3 = nil
        @val4 = nil
      end
      def onStatusTextChange(t)
        @val1 = t
      end
      def onProgressChange(p, pmax)
        @val2 = p
        @val3 = pmax
      end
      def onPropertyChange(p)
        @val4 = p
      end
    end

    class Handler2
      attr_reader :ev
      def initialize
        @ev = ""
      end
      def method_missing(ev, *arg)
        @ev += ev
      end
    end

    def test_handler1
      ev = WIN32OLE_EVENT.new(@ie)
      h1 = Handler1.new
      ev.handler = h1
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert(h1.val1)
      assert_equal(h1.val1, ev.handler.val1)
      assert(h1.val2)
      assert(h1.val3)
      assert(h1.val4)
    end

    def test_handler2
      ev = WIN32OLE_EVENT.new(@ie)
      h2 = Handler2.new
      ev.handler = h2
      @ie.navigate("file:///#{@f}")
      wait_ie
      assert(h2.ev != "")
    end

  end
end
