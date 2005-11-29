require 'observer'

module DRb
  module DRbObservable
    include Observable

    def notify_observers(*arg)
      if defined? @observer_state and @observer_state
        if defined? @observer_peers
          @observer_peers.delete_if do |k, v|
            begin
              k.send(v, *arg)
              false
            rescue
              true
            end
          end
        end
        @observer_state = false
      end
    end
  end
end
