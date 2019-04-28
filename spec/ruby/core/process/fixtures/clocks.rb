module ProcessSpecs
  def self.clock_constants
    clocks = []

    platform_is_not :windows, :solaris do
      clocks += Process.constants.select { |c| c.to_s.start_with?('CLOCK_') }

      # These require CAP_WAKE_ALARM and are not documented in
      # Process#clock_gettime. They return EINVAL if the permission
      # is not granted.
      clocks -= [:CLOCK_BOOTTIME_ALARM, :CLOCK_REALTIME_ALARM]
    end

    clocks.map { |c|
      [c, Process.const_get(c)]
    }
  end

  def self.clock_constants_for_resolution_checks
    clocks = clock_constants

    # These clocks in practice on Linux do not seem to match their reported resolution.
    platform_is :linux do
      clocks = clocks.reject { |clock, value|
        [:CLOCK_REALTIME_COARSE, :CLOCK_MONOTONIC_COARSE].include?(clock)
      }
    end

    # These clocks in practice on macOS seem to be less precise than advertised by clock_getres
    platform_is :darwin do
      clocks = clocks.reject { |clock, value|
        [:CLOCK_UPTIME_RAW_APPROX].include?(clock)
      }
    end

    # These clocks in practice on ARM on Linux do not seem to match their reported resolution.
    platform_is :armv7l, :aarch64 do
      clocks = clocks.reject { |clock, value|
        [:CLOCK_PROCESS_CPUTIME_ID, :CLOCK_THREAD_CPUTIME_ID, :CLOCK_MONOTONIC_RAW].include?(clock)
      }
    end

    # CentOS seems to report a negative resolution for CLOCK_MONOTONIC_RAW
    platform_is :linux do
      clocks = clocks.reject { |clock, value|
        clock == :CLOCK_MONOTONIC_RAW and Process.clock_getres(value, :nanosecond) < 0
      }
    end

    clocks
  end
end
