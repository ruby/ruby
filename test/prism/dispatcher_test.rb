# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class DispatcherTest < TestCase
    class TestListener
      attr_reader :events_received

      def initialize
        @events_received = []
      end

      def on_call_node_enter(node)
        events_received << :on_call_node_enter
      end

      def on_call_node_leave(node)
        events_received << :on_call_node_leave
      end

      def on_integer_node_enter(node)
        events_received << :on_integer_node_enter
      end
    end

    def test_dispatching_events
      listener = TestListener.new
      dispatcher = Dispatcher.new
      dispatcher.register(listener, :on_call_node_enter, :on_call_node_leave, :on_integer_node_enter)

      root = Prism.parse(<<~RUBY).value
        def foo
          something(1, 2, 3)
        end
      RUBY

      dispatcher.dispatch(root)
      assert_equal([:on_call_node_enter, :on_integer_node_enter, :on_integer_node_enter, :on_integer_node_enter, :on_call_node_leave], listener.events_received)

      listener.events_received.clear
      dispatcher.dispatch_once(root.statements.body.first.body.body.first)
      assert_equal([:on_call_node_enter, :on_call_node_leave], listener.events_received)
    end
  end
end
