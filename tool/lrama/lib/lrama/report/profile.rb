module Lrama
  class Report
    module Profile
      # See "Profiling Lrama" in README.md for how to use.
      def self.report_profile
        require "stackprof"

        StackProf.run(mode: :cpu, raw: true, out: 'tmp/stackprof-cpu-myapp.dump') do
          yield
        end
      end
    end
  end
end
