require_relative '../../spec_helper'

describe "Process.clock_gettime" do
  platform_is_not :windows, :solaris do
    Process.constants.select { |c|
      c.to_s.start_with?('CLOCK_') &&
      # These require CAP_WAKE_ALARM and are not documented in clock_gettime(),
      # they return EINVAL if the permission is not granted.
      c != :CLOCK_BOOTTIME_ALARM &&
      c != :CLOCK_REALTIME_ALARM
    }.each do |c|
      it "can be called with Process::#{c}" do
        value = Process.const_get(c)
        Process.clock_gettime(value).should be_an_instance_of(Float)
      end
    end
  end

  describe 'time units' do
    it 'handles a fixed set of time units' do
      [:nanosecond, :microsecond, :millisecond, :second].each do |unit|
        Process.clock_gettime(Process::CLOCK_MONOTONIC, unit).should be_kind_of(Integer)
      end

      [:float_microsecond, :float_millisecond, :float_second].each do |unit|
        Process.clock_gettime(Process::CLOCK_MONOTONIC, unit).should be_an_instance_of(Float)
      end
    end

    it 'raises an ArgumentError for an invalid time unit' do
      lambda { Process.clock_gettime(Process::CLOCK_MONOTONIC, :bad) }.should raise_error(ArgumentError)
    end

    it 'defaults to :float_second' do
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)

      t1.should be_an_instance_of(Float)
      t2.should be_close(t1, 2.0)  # 2.0 is chosen arbitrarily to allow for time skew without admitting failure cases, which would be off by an order of magnitude.
    end

    it 'uses the default time unit (:float_second) when passed nil' do
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC, nil)
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)

      t1.should be_an_instance_of(Float)
      t2.should be_close(t1, 2.0) # 2.0 is chosen arbitrarily to allow for time skew without admitting failure cases, which would be off by an order of magnitude.
    end
  end
end
