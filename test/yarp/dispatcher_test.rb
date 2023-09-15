# frozen_string_literal: true

require_relative "test_helper"

module YARP
  class DispatcherTest < TestCase
    class TestListener
      attr_reader :events_received

      def initialize
        @events_received = []
      end

      def call_node_enter(node)
        events_received << :call_node_enter
      end

      def call_node_leave(node)
        events_received << :call_node_leave
      end
    end

    def test_dispatching_events
      listener = TestListener.new

      dispatcher = Dispatcher.new
      dispatcher.register(listener, :call_node_enter, :call_node_leave)

      root = YARP.parse(<<~RUBY).value
        def foo
          something(1, 2, 3)
        end
      RUBY

      dispatcher.dispatch(root)
      assert_equal([:call_node_enter, :call_node_leave], listener.events_received)
    end
  end
end
