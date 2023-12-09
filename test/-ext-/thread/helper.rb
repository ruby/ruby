module ThreadInstrumentation
  module TestHelper
    private

    def record
      Bug::ThreadInstrumentation.register_callback(!ENV["GVL_DEBUG"])
      yield
    ensure
      timeline = Bug::ThreadInstrumentation.unregister_callback
      if $!
        raise
      else
        return timeline
      end
    end

    def timeline_for(thread, timeline)
      timeline.select { |t, _| t == thread }.map(&:last)
    end

    def assert_consistent_timeline(events)
      refute_predicate events, :empty?

      previous_event = nil
      events.each do |event|
        refute_equal :exited, previous_event, "`exited` must be the final event: #{events.inspect}"
        case event
        when :started
          assert_nil previous_event, "`started` must be the first event: #{events.inspect}"
        when :ready
          unless previous_event.nil?
            assert %i(started suspended).include?(previous_event), "`ready` must be preceded by `started` or `suspended`: #{events.inspect}"
          end
        when :resumed
          unless previous_event.nil?
            assert_equal :ready, previous_event, "`resumed` must be preceded by `ready`: #{events.inspect}"
          end
        when :suspended
          unless previous_event.nil?
            assert_equal :resumed, previous_event, "`suspended` must be preceded by `resumed`: #{events.inspect}"
          end
        when :exited
          unless previous_event.nil?
            assert %i(resumed suspended).include?(previous_event), "`exited` must be preceded by `resumed` or `suspended`: #{events.inspect}"
          end
        end
        previous_event = event
      end
    end
  end
end
