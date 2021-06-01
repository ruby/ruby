require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/now'
require_relative 'shared/local'
require_relative 'shared/time_params'

describe "Time.new" do
  it_behaves_like :time_now, :new
end

describe "Time.new" do
  it_behaves_like :time_local, :new
  it_behaves_like :time_params, :new
end

describe "Time.new with a utc_offset argument" do
  it "returns a non-UTC time" do
    Time.new(2000, 1, 1, 0, 0, 0, 0).should_not.utc?
  end

  it "returns a Time with a UTC offset of the specified number of Integer seconds" do
    Time.new(2000, 1, 1, 0, 0, 0, 123).utc_offset.should == 123
  end

  describe "with an argument that responds to #to_int" do
    it "coerces using #to_int" do
      o = mock('integer')
      o.should_receive(:to_int).and_return(123)
      Time.new(2000, 1, 1, 0, 0, 0, o).utc_offset.should == 123
    end
  end

  it "returns a Time with a UTC offset of the specified number of Rational seconds" do
    Time.new(2000, 1, 1, 0, 0, 0, Rational(5, 2)).utc_offset.should eql(Rational(5, 2))
  end

  describe "with an argument that responds to #to_r" do
    it "coerces using #to_r" do
      o = mock_numeric('rational')
      o.should_receive(:to_r).and_return(Rational(5, 2))
      Time.new(2000, 1, 1, 0, 0, 0, o).utc_offset.should eql(Rational(5, 2))
    end
  end

  it "returns a Time with a UTC offset specified as +HH:MM" do
    Time.new(2000, 1, 1, 0, 0, 0, "+05:30").utc_offset.should == 19800
  end

  it "returns a Time with a UTC offset specified as -HH:MM" do
    Time.new(2000, 1, 1, 0, 0, 0, "-04:10").utc_offset.should == -15000
  end

  it "returns a Time with a UTC offset specified as +HH:MM:SS" do
    Time.new(2000, 1, 1, 0, 0, 0, "+05:30:37").utc_offset.should == 19837
  end

  it "returns a Time with a UTC offset specified as -HH:MM" do
    Time.new(2000, 1, 1, 0, 0, 0, "-04:10:43").utc_offset.should == -15043
  end

  describe "with an argument that responds to #to_str" do
    it "coerces using #to_str" do
      o = mock('string')
      o.should_receive(:to_str).and_return("+05:30")
      Time.new(2000, 1, 1, 0, 0, 0, o).utc_offset.should == 19800
    end
  end

  it "returns a local Time if the argument is nil" do
    with_timezone("PST", -8) do
      t = Time.new(2000, 1, 1, 0, 0, 0, nil)
      t.utc_offset.should == -28800
      t.zone.should == "PST"
    end
  end

  # [Bug #8679], r47676
  it "disallows a value for minutes greater than 59" do
    -> {
      Time.new(2000, 1, 1, 0, 0, 0, "+01:60")
    }.should raise_error(ArgumentError)
    -> {
      Time.new(2000, 1, 1, 0, 0, 0, "+01:99")
    }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the String argument is not of the form (+|-)HH:MM" do
    -> { Time.new(2000, 1, 1, 0, 0, 0, "3600") }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the hour value is greater than 23" do
    -> { Time.new(2000, 1, 1, 0, 0, 0, "+24:00") }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the String argument is not in an ASCII-compatible encoding" do
    -> { Time.new(2000, 1, 1, 0, 0, 0, "-04:10".encode("UTF-16LE")) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the argument represents a value less than or equal to -86400 seconds" do
    Time.new(2000, 1, 1, 0, 0, 0, -86400 + 1).utc_offset.should == (-86400 + 1)
    -> { Time.new(2000, 1, 1, 0, 0, 0, -86400) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the argument represents a value greater than or equal to 86400 seconds" do
    Time.new(2000, 1, 1, 0, 0, 0, 86400 - 1).utc_offset.should == (86400 - 1)
    -> { Time.new(2000, 1, 1, 0, 0, 0, 86400) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the seconds argument is negative" do
    -> { Time.new(2000, 1, 1, 0, 0, -1) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the utc_offset argument is greater than or equal to 10e9" do
    -> { Time.new(2000, 1, 1, 0, 0, 0, 1000000000) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the month is greater than 12" do
    # For some reason MRI uses a different message for month in 13-15 and month>=16
    -> { Time.new(2000, 13, 1, 0, 0, 0, "+01:00") }.should raise_error(ArgumentError, /(mon|argument) out of range/)
    -> { Time.new(2000, 16, 1, 0, 0, 0, "+01:00") }.should raise_error(ArgumentError, "argument out of range")
  end
end

ruby_version_is "2.6" do
  describe "Time.new with a timezone argument" do
    it "returns a Time in the timezone" do
      zone = TimeSpecs::Timezone.new(offset: (5*3600+30*60))
      time = Time.new(2000, 1, 1, 12, 0, 0, zone)

      time.zone.should == zone
      time.utc_offset.should == 5*3600+30*60
      ruby_version_is "3.0" do
        time.wday.should == 6
        time.yday.should == 1
      end
    end

    it "accepts timezone argument that must have #local_to_utc and #utc_to_local methods" do
      zone = Object.new
      def zone.utc_to_local(time)
        time
      end
      def zone.local_to_utc(time)
        time
      end

      -> {
        Time.new(2000, 1, 1, 12, 0, 0, zone).should be_kind_of(Time)
      }.should_not raise_error
    end

    it "raises TypeError if timezone does not implement #local_to_utc method" do
      zone = Object.new
      def zone.utc_to_local(time)
        time
      end

      -> {
        Time.new(2000, 1, 1, 12, 0, 0, zone)
      }.should raise_error(TypeError, /can't convert \w+ into an exact number/)
    end

    it "does not raise exception if timezone does not implement #utc_to_local method" do
      zone = Object.new
      def zone.local_to_utc(time)
        time
      end

      -> {
        Time.new(2000, 1, 1, 12, 0, 0, zone).should be_kind_of(Time)
      }.should_not raise_error
    end

    # The result also should be a Time or Time-like object (not necessary to be the same class)
    # The zone of the result is just ignored
    describe "returned value by #utc_to_local and #local_to_utc methods" do
      it "could be Time instance" do
        zone = Object.new
        def zone.local_to_utc(t)
          Time.utc(t.year, t.mon, t.day, t.hour - 1, t.min, t.sec)
        end

        -> {
          Time.new(2000, 1, 1, 12, 0, 0, zone).should be_kind_of(Time)
          Time.new(2000, 1, 1, 12, 0, 0, zone).utc_offset.should == 60*60
        }.should_not raise_error
      end

      it "could be Time subclass instance" do
        zone = Object.new
        def zone.local_to_utc(t)
          Class.new(Time).utc(t.year, t.mon, t.day, t.hour - 1, t.min, t.sec)
        end

        -> {
          Time.new(2000, 1, 1, 12, 0, 0, zone).should be_kind_of(Time)
          Time.new(2000, 1, 1, 12, 0, 0, zone).utc_offset.should == 60*60
        }.should_not raise_error
      end

      it "could be any object with #to_i method" do
        zone = Object.new
        def zone.local_to_utc(time)
          Struct.new(:to_i).new(time.to_i - 60*60)
        end

        -> {
          Time.new(2000, 1, 1, 12, 0, 0, zone).should be_kind_of(Time)
          Time.new(2000, 1, 1, 12, 0, 0, zone).utc_offset.should == 60*60
        }.should_not raise_error
      end

      it "could have any #zone and #utc_offset because they are ignored" do
        zone = Object.new
        def zone.local_to_utc(time)
          Struct.new(:to_i, :zone, :utc_offset).new(time.to_i, 'America/New_York', -5*60*60)
        end
        Time.new(2000, 1, 1, 12, 0, 0, zone).utc_offset.should == 0

        zone = Object.new
        def zone.local_to_utc(time)
          Struct.new(:to_i, :zone, :utc_offset).new(time.to_i, 'Asia/Tokyo', 9*60*60)
        end
        Time.new(2000, 1, 1, 12, 0, 0, zone).utc_offset.should == 0
      end

      it "leads to raising Argument error if difference between argument and result is too large" do
        zone = Object.new
        def zone.local_to_utc(t)
          Time.utc(t.year, t.mon, t.day + 1, t.hour, t.min, t.sec)
        end

        -> {
          Time.new(2000, 1, 1, 12, 0, 0, zone)
        }.should raise_error(ArgumentError, "utc_offset out of range")
      end
    end

    # https://github.com/ruby/ruby/blob/v2_6_0/time.c#L5330
    #
    # Time-like argument to these methods is similar to a Time object in UTC without sub-second;
    # it has attribute readers for the parts, e.g. year, month, and so on, and epoch time readers, to_i
    #
    # The sub-second attributes are fixed as 0, and utc_offset, zone, isdst, and their aliases are same as a Time object in UTC
    describe "Time-like argument of #utc_to_local and #local_to_utc methods" do
      before do
        @obj = TimeSpecs::TimeLikeArgumentRecorder.result
        @obj.should_not == nil
      end

      it "implements subset of Time methods" do
        [
          :year, :mon, :month, :mday, :hour, :min, :sec,
          :tv_sec, :tv_usec, :usec, :tv_nsec, :nsec, :subsec,
          :to_i, :to_f, :to_r, :+, :-,
          :isdst, :dst?, :zone, :gmtoff, :gmt_offset, :utc_offset, :utc?, :gmt?,
          :to_s, :inspect, :to_a, :to_time,
        ].each do |name|
          @obj.respond_to?(name).should == true
        end
      end

      it "has attribute values the same as a Time object in UTC" do
        @obj.usec.should == 0
        @obj.nsec.should == 0
        @obj.subsec.should == 0
        @obj.tv_usec.should == 0
        @obj.tv_nsec.should == 0

        @obj.utc_offset.should == 0
        @obj.zone.should == "UTC"
        @obj.isdst.should == Time.new.utc.isdst
      end
    end

    context "#name method" do
      it "uses the optional #name method for marshaling" do
        zone = TimeSpecs::TimezoneWithName.new(name: "Asia/Colombo")
        time = Time.new(2000, 1, 1, 12, 0, 0, zone)
        time_loaded = Marshal.load(Marshal.dump(time))

        time_loaded.zone.should == "Asia/Colombo"
        time_loaded.utc_offset.should == 5*3600+30*60
      end

      it "cannot marshal Time if #name method isn't implemented" do
        zone = TimeSpecs::Timezone.new(offset: (5*3600+30*60))
        time = Time.new(2000, 1, 1, 12, 0, 0, zone)

        -> {
          Marshal.dump(time)
        }.should raise_error(NoMethodError, /undefined method `name' for/)
      end
    end

    it "the #abbr method is used by '%Z' in #strftime" do
      zone = TimeSpecs::TimezoneWithAbbr.new(name: "Asia/Colombo")
      time = Time.new(2000, 1, 1, 12, 0, 0, zone)

      time.strftime("%Z").should == "MMT"
    end

    # At loading marshaled data, a timezone name will be converted to a timezone object
    # by find_timezone class method, if the method is defined.
    # Similarly, that class method will be called when a timezone argument does not have
    # the necessary methods mentioned above.
    context "subject's class implements .find_timezone method" do
      it "calls .find_timezone to build a time object at loading marshaled data" do
        zone = TimeSpecs::TimezoneWithName.new(name: "Asia/Colombo")
        time = TimeSpecs::TimeWithFindTimezone.new(2000, 1, 1, 12, 0, 0, zone)
        time_loaded = Marshal.load(Marshal.dump(time))

        time_loaded.zone.should be_kind_of TimeSpecs::TimezoneWithName
        time_loaded.zone.name.should == "Asia/Colombo"
        time_loaded.utc_offset.should == 5*3600+30*60
      end

      it "calls .find_timezone to build a time object if passed zone name as a timezone argument" do
        time = TimeSpecs::TimeWithFindTimezone.new(2000, 1, 1, 12, 0, 0, "Asia/Colombo")
        time.zone.should be_kind_of TimeSpecs::TimezoneWithName
        time.zone.name.should == "Asia/Colombo"

        time = TimeSpecs::TimeWithFindTimezone.new(2000, 1, 1, 12, 0, 0, "some invalid zone name")
        time.zone.should be_kind_of TimeSpecs::TimezoneWithName
        time.zone.name.should == "some invalid zone name"
      end

      it "does not call .find_timezone if passed any not string/numeric/timezone timezone argument" do
        [Object.new, [], {}, :"some zone"].each do |zone|
          -> {
            TimeSpecs::TimeWithFindTimezone.new(2000, 1, 1, 12, 0, 0, zone)
          }.should raise_error(TypeError, /can't convert \w+ into an exact number/)
        end
      end
    end
  end
end
