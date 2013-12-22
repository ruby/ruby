begin
  require 'win32ole'
rescue LoadError
end
require 'test/unit'

if defined?(WIN32OLE)
  class TestThread < Test::Unit::TestCase
    #
    # test for Bug #2618(ruby-core:27634)
    #
    def assert_creating_win32ole_object_in_thread(meth)
      t = Thread.__send__(meth) {
        WIN32OLE.new('Scripting.Dictionary')
      }
      assert_nothing_raised(WIN32OLERuntimeError, "[Bug #2618] Thread.#{meth}") {
        t.join
      }
    end

    def test_creating_win32ole_object_in_thread_new
      assert_creating_win32ole_object_in_thread(:new)
    end

    def test_creating_win32ole_object_in_thread_start
      assert_creating_win32ole_object_in_thread(:start)
    end

    def test_creating_win32ole_object_in_thread_fork
      assert_creating_win32ole_object_in_thread(:fork)
    end
  end
end
