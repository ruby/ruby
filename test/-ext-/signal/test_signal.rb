# frozen_string_literal: false
require 'test/unit'
require '-test-/signal'

class TestSignalInspection < Test::Unit::TestCase
  def setup
    omit 'requires sigaction and SIGCHLD' unless Bug::Signal.respond_to?(:with_handler) && Signal.list.key?('CHLD')
  end

  def test_preserves_native_handler
    assert_separately([], <<~'RUBY')
      require '-test-/signal'
      signo = Signal.list.fetch('CHLD')
      Signal.trap(signo, 'DEFAULT')

      Bug::Signal.with_handler(signo) do
        before = Bug::Signal.handler_state(signo)
        assert_nil Signal[signo]
        assert_equal before, Bug::Signal.handler_state(signo)
      end
    RUBY
  end

  def test_preserves_pending_signal
    assert_separately([], <<~'RUBY')
      require '-test-/signal'
      signo = Signal.list.fetch('CHLD')
      Signal.trap(signo, 'DEFAULT')

      Bug::Signal.with_pending_signal(signo) do
        assert Bug::Signal.pending?(signo), 'SIGCHLD should be pending before inspection'
        assert_equal 'DEFAULT', Signal[signo]
        assert Bug::Signal.pending?(signo), 'Signal[] discarded the pending SIGCHLD'
      end
    RUBY
  end
end
