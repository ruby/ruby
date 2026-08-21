class Bundler::ConnectionPool
  class Wrapper < ::BasicObject
    METHODS = [:with, :pool_shutdown, :wrapped_pool]

    def initialize(**options, &)
      @pool = options.fetch(:pool) { ::Bundler::ConnectionPool.new(**options, &) }
    end

    def wrapped_pool
      @pool
    end

    def with(**, &)
      @pool.with(**, &)
    end

    def pool_shutdown(&)
      @pool.shutdown(&)
    end

    def pool_size
      @pool.size
    end

    def pool_available
      @pool.available
    end

    def respond_to?(id, *, **)
      METHODS.include?(id) || with { |c| c.respond_to?(id, *, **) }
    end

    def respond_to_missing?(id, *, **)
      with { |c| c.respond_to?(id, *, **) }
    end

    def method_missing(name, *, **, &)
      with do |connection|
        connection.send(name, *, **, &)
      end
    end
  end
end
