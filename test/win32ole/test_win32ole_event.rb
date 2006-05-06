begin
  require 'win32ole'
rescue LoadError
end
require 'test/unit'

if defined?(WIN32OLE_EVENT)
  class TestWIN32OLE_EVENT < Test::Unit::TestCase
    def setup
      @ie = WIN32OLE.new("InternetExplorer.Application")
      @ie.visible = true
      @event = ""
      @event2 = ""
      @event3 = ""
    end

    def default_handler(event, *args)
      @event += event
    end

    def test_on_event
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event {|*args| default_handler(*args)}
      @ie.gohome
      while @ie.busy
        WIN32OLE_EVENT.message_loop
      end
      assert_match(/BeforeNavigate/, @event)
      assert_match(/NavigateComplete/, @event)
    end

    def test_on_event2
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event('BeforeNavigate') {|*args| handler1}
      ev.on_event('BeforeNavigate') {|*args| handler2}
      @ie.gohome
      while @ie.busy
        WIN32OLE_EVENT.message_loop
      end
      assert_equal("handler2", @event2)
    end

    def test_on_event3
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event {handler1}
      ev.on_event {handler2}
      @ie.gohome
      while @ie.busy
        WIN32OLE_EVENT.message_loop
      end
      assert_equal("handler2", @event2)
    end

    def test_on_event4
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event{handler1}
      ev.on_event{handler2}
      ev.on_event('NavigateComplete'){|*args| handler3(*args)}
      @ie.gohome
      while @ie.busy
        WIN32OLE_EVENT.message_loop
      end
      assert(@event3!="")
      assert("handler2", @event2)
    end

    def test_on_event5
      ev = WIN32OLE_EVENT.new(@ie, 'DWebBrowserEvents')
      ev.on_event {|*args| default_handler(*args)}
      ev.on_event('NavigateComplete'){|*args| handler3(*args)}
      @ie.gohome
      while @ie.busy
        WIN32OLE_EVENT.message_loop
      end
      assert_match(/BeforeNavigate/, @event)
      assert(/NavigateComplete/ !~ @event)
      assert(@event!="")
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
      GC.start
      sleep 1
    end
  end
end
