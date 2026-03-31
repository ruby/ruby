# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Reporter
    module Profile
      module Memory
        # See "Memory Profiling Lrama" in README.md for how to use.
        #
        # @rbs enabled: bool
        # @rbs &: -> void
        # @rbs return: StackProf::result | void
        def self.report(enabled)
          if enabled && require_memory_profiler
            ex = nil #: Exception?

            report = MemoryProfiler.report do # steep:ignore UnknownConstant
              yield
            rescue Exception => e
              ex = e
            end

            report.pretty_print(to_file: "tmp/memory_profiler.txt")

            if ex
              raise ex
            end
          else
            yield
          end
        end

        # @rbs return: bool
        def self.require_memory_profiler
          require "memory_profiler"
          true
        rescue LoadError
          warn "memory_profiler is not installed. Please run `bundle install`."
          false
        end
      end
    end
  end
end
