module Lrama
  class Report
    module Duration
      def self.enable
        @_report_duration_enabled = true
      end

      def self.enabled?
        !!@_report_duration_enabled
      end

      def report_duration(method_name)
        time1 = Time.now.to_f
        result = yield
        time2 = Time.now.to_f

        if Duration.enabled?
          puts sprintf("%s %10.5f s", method_name, time2 - time1)
        end

        return result
      end
    end
  end
end
