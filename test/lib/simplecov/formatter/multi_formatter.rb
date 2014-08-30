module SimpleCov
  module Formatter
    class MultiFormatter
      def self.[](*args)
        Class.new(self) do
          define_method :formatters do
            @formatters ||= args
          end
        end
      end

      def format(result)
        formatters.map do |formatter|
          begin
            formatter.new.format(result)
          rescue => e
            STDERR.puts("Formatter #{formatter} failed with #{e.class}: #{e.message} (#{e.backtrace.first})")
            nil
          end
        end
      end

      def formatters
        @formatters ||= []
      end
    end
  end
end
