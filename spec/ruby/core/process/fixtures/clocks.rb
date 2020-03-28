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

    clocks.sort.map { |c|
      [c, Process.const_get(c)]
    }
  end
end
