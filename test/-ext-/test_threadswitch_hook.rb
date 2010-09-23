require 'test/unit'
require '-test-/threadswitch/event_hook'
require 'ruby/envutil'

class Test_ThreadSwitch < Test::Unit::TestCase
  def test_threadswitch_init
    threads = []
    warning = EnvUtil.verbose_warning {
      EventHook::ThreadSwitch.hook {|name, thread|
        threads << thread if name == "thread-init"
      }
    }
    assert_match(/not an official API/, warning)
    assert_operator(threads, :include?, Thread.current)
  end
end
