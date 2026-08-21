class Bundler::ConnectionPool
  if Process.respond_to?(:fork)
    INSTANCES = ObjectSpace::WeakMap.new
    private_constant :INSTANCES

    def self.after_fork
      INSTANCES.each_value do |pool|
        # We're in after_fork, so we know all other threads are dead.
        # All we need to do is ensure the main thread doesn't have a
        # checked out connection
        pool.checkin(force: true)
        pool.reload do |connection|
          # Unfortunately we don't know what method to call to close the connection,
          # so we try the most common one.
          connection.close if connection.respond_to?(:close)
        end
      end
      nil
    end

    module ForkTracker
      def _fork
        pid = super
        if pid == 0
          Bundler::ConnectionPool.after_fork
        end
        pid
      end
    end
    Process.singleton_class.prepend(ForkTracker)
  else
    # JRuby, et al
    INSTANCES = nil
    private_constant :INSTANCES

    def self.after_fork
      # noop
    end
  end
end
