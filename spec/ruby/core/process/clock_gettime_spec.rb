require_relative '../../spec_helper'
require_relative 'fixtures/clocks'

describe "Process.clock_gettime" do
  ProcessSpecs.clock_constants.each do |name, value|
    it "can be called with Process::#{name}" do
      Process.clock_gettime(value).should be_an_instance_of(Float)
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
      -> { Process.clock_gettime(Process::CLOCK_MONOTONIC, :bad) }.should raise_error(ArgumentError)
    end

    it 'defaults to :float_second' do
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)

      t1.should be_an_instance_of(Float)
      t2.should be_an_instance_of(Float)
      t2.should be_close(t1, TIME_TOLERANCE)
    end

    it 'uses the default time unit (:float_second) when passed nil' do
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC, nil)
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)

      t1.should be_an_instance_of(Float)
      t2.should be_an_instance_of(Float)
      t2.should be_close(t1, TIME_TOLERANCE)
    end
  end

  describe "supports the platform clocks mentioned in the documentation" do
    it "CLOCK_REALTIME" do
      Process.clock_gettime(Process::CLOCK_REALTIME).should be_an_instance_of(Float)
    end

    it "CLOCK_MONOTONIC" do
      Process.clock_gettime(Process::CLOCK_MONOTONIC).should be_an_instance_of(Float)
    end

    # These specs need macOS 10.12+ / darwin 16+
    guard -> { platform_is_not(:darwin) or kernel_version_is '16' } do
      platform_is :linux, :openbsd, :darwin do
        it "CLOCK_PROCESS_CPUTIME_ID" do
          Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID).should be_an_instance_of(Float)
        end
      end

      platform_is :linux, :freebsd, :openbsd, :darwin do
        it "CLOCK_THREAD_CPUTIME_ID" do
          Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID).should be_an_instance_of(Float)
        end
      end

      platform_is :linux, :darwin do
        it "CLOCK_MONOTONIC_RAW" do
          Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW).should be_an_instance_of(Float)
        end
      end

      platform_is :darwin do
        it "CLOCK_MONOTONIC_RAW_APPROX" do
          Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW_APPROX).should be_an_instance_of(Float)
        end

        it "CLOCK_UPTIME_RAW and CLOCK_UPTIME_RAW_APPROX" do
          Process.clock_gettime(Process::CLOCK_UPTIME_RAW).should be_an_instance_of(Float)
          Process.clock_gettime(Process::CLOCK_UPTIME_RAW_APPROX).should be_an_instance_of(Float)
        end
      end
    end

    platform_is :freebsd do
      it "CLOCK_VIRTUAL" do
        Process.clock_gettime(Process::CLOCK_VIRTUAL).should be_an_instance_of(Float)
      end

      it "CLOCK_PROF" do
        Process.clock_gettime(Process::CLOCK_PROF).should be_an_instance_of(Float)
      end
    end

    platform_is :freebsd, :openbsd do
      it "CLOCK_UPTIME" do
        Process.clock_gettime(Process::CLOCK_UPTIME).should be_an_instance_of(Float)
      end
    end

    platform_is :freebsd do
      it "CLOCK_REALTIME_FAST and CLOCK_REALTIME_PRECISE" do
        Process.clock_gettime(Process::CLOCK_REALTIME_FAST).should be_an_instance_of(Float)
        Process.clock_gettime(Process::CLOCK_REALTIME_PRECISE).should be_an_instance_of(Float)
      end

      it "CLOCK_MONOTONIC_FAST and CLOCK_MONOTONIC_PRECISE" do
        Process.clock_gettime(Process::CLOCK_MONOTONIC_FAST).should be_an_instance_of(Float)
        Process.clock_gettime(Process::CLOCK_MONOTONIC_PRECISE).should be_an_instance_of(Float)
      end

      it "CLOCK_UPTIME_FAST and CLOCK_UPTIME_PRECISE" do
        Process.clock_gettime(Process::CLOCK_UPTIME_FAST).should be_an_instance_of(Float)
        Process.clock_gettime(Process::CLOCK_UPTIME_PRECISE).should be_an_instance_of(Float)
      end

      it "CLOCK_SECOND" do
        Process.clock_gettime(Process::CLOCK_SECOND).should be_an_instance_of(Float)
      end
    end

    guard -> { platform_is :linux and kernel_version_is '2.6.32' } do
      it "CLOCK_REALTIME_COARSE" do
        Process.clock_gettime(Process::CLOCK_REALTIME_COARSE).should be_an_instance_of(Float)
      end

      it "CLOCK_MONOTONIC_COARSE" do
        Process.clock_gettime(Process::CLOCK_MONOTONIC_COARSE).should be_an_instance_of(Float)
      end
    end

    guard -> { platform_is :linux and kernel_version_is '2.6.39' } do
      it "CLOCK_BOOTTIME" do
        skip "No Process::CLOCK_BOOTTIME" unless defined?(Process::CLOCK_BOOTTIME)
        Process.clock_gettime(Process::CLOCK_BOOTTIME).should be_an_instance_of(Float)
      end
    end

    guard -> { platform_is "x86_64-linux" and kernel_version_is '3.0' } do
      it "CLOCK_REALTIME_ALARM" do
        skip "No Process::CLOCK_REALTIME_ALARM" unless defined?(Process::CLOCK_REALTIME_ALARM)
        Process.clock_gettime(Process::CLOCK_REALTIME_ALARM).should be_an_instance_of(Float)
      end

      it "CLOCK_BOOTTIME_ALARM" do
        skip "No Process::CLOCK_BOOTTIME_ALARM" unless defined?(Process::CLOCK_BOOTTIME_ALARM)
        Process.clock_gettime(Process::CLOCK_BOOTTIME_ALARM).should be_an_instance_of(Float)
      end
    end
  end
end
