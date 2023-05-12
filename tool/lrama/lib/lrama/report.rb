module Lrama
  class Report
    module Profile
      # 1. Wrap target method with Profile.report_profile like below:
      #
      #   Lrama::Report::Profile.report_profile { method }
      #
      # 2. Run lrama command, for example
      #
      #   $ ./exe/lrama --trace=time spec/fixtures/integration/ruby_3_2_0/parse.tmp.y
      #
      # 3. Generate html file
      #
      #   $ stackprof --d3-flamegraph tmp/stackprof-cpu-myapp.dump > tmp/flamegraph.html
      #
      def self.report_profile
        require "stackprof"

        StackProf.run(mode: :cpu, raw: true, out: 'tmp/stackprof-cpu-myapp.dump') do
          yield
        end
      end
    end

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
