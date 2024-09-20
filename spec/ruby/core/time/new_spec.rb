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

  ruby_bug '#13669', ''...'3.1' do
    it "returns a Time with a UTC offset specified as +HH" do
      Time.new(2000, 1, 1, 0, 0, 0, "+05").utc_offset.should == 3600 * 5
    end

    it "returns a Time with a UTC offset specified as -HH" do
      Time.new(2000, 1, 1, 0, 0, 0, "-05").utc_offset.should == -3600 * 5
    end

    it "returns a Time with a UTC offset specified as +HHMM" do
      Time.new(2000, 1, 1, 0, 0, 0, "+0530").utc_offset.should == 19800
    end

    it "returns a Time with a UTC offset specified as -HHMM" do
      Time.new(2000, 1, 1, 0, 0, 0, "-0530").utc_offset.should == -19800
    end

    it "returns a Time with a UTC offset specified as +HHMMSS" do
      Time.new(2000, 1, 1, 0, 0, 0, "+053037").utc_offset.should == 19837
    end

    it "returns a Time with a UTC offset specified as -HHMMSS" do
      Time.new(2000, 1, 1, 0, 0, 0, "-053037").utc_offset.should == -19837
    end
  end

  describe "with an argument that responds to #to_str" do
    it "coerces using #to_str" do
      o = mock('string')
      o.should_receive(:to_str).and_return("+05:30")
      Time.new(2000, 1, 1, 0, 0, 0, o).utc_offset.should == 19800
    end
  end

  it "returns a Time with UTC offset specified as UTC" do
    Time.new(2000, 1, 1, 0, 0, 0, "UTC").utc_offset.should == 0
  end

  it "returns a Time with UTC offset specified as a single letter military timezone" do
    [
      ["A", 3600],
      ["B", 3600 * 2],
      ["C", 3600 * 3],
      ["D", 3600 * 4],
      ["E", 3600 * 5],
      ["F", 3600 * 6],
      ["G", 3600 * 7],
      ["H", 3600 * 8],
      ["I", 3600 * 9],
      # J is not supported
      ["K", 3600 * 10],
      ["L", 3600 * 11],
      ["M", 3600 * 12],
      ["N", 3600 * -1],
      ["O", 3600 * -2],
      ["P", 3600 * -3],
      ["Q", 3600 * -4],
      ["R", 3600 * -5],
      ["S", 3600 * -6],
      ["T", 3600 * -7],
      ["U", 3600 * -8],
      ["V", 3600 * -9],
      ["W", 3600 * -10],
      ["X", 3600 * -11],
      ["Y", 3600 * -12],
      ["Z", 0]
    ].each do |letter, offset|
      Time.new(2000, 1, 1, 0, 0, 0, letter).utc_offset.should == offset
    end
  end

  ruby_version_is ""..."3.1" do
    it "raises ArgumentError if the string argument is J" do
      message = '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset'
      -> { Time.new(2000, 1, 1, 0, 0, 0, "J") }.should raise_error(ArgumentError, message)
    end
  end

  ruby_version_is "3.1" do
    it "raises ArgumentError if the string argument is J" do
      message = '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: J'
      -> { Time.new(2000, 1, 1, 0, 0, 0, "J") }.should raise_error(ArgumentError, message)
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
    # Don't check exception message - it was changed in previous CRuby versions:
    # - "string contains null byte"
    # - '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset'
    -> {
      Time.new(2000, 1, 1, 0, 0, 0, "-04:10".encode("UTF-16LE"))
    }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the argument represents a value less than or equal to -86400 seconds" do
    Time.new(2000, 1, 1, 0, 0, 0, -86400 + 1).utc_offset.should == (-86400 + 1)
    -> { Time.new(2000, 1, 1, 0, 0, 0, -86400) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the argument represents a value greater than or equal to 86400 seconds" do
    Time.new(2000, 1, 1, 0, 0, 0, 86400 - 1).utc_offset.should == (86400 - 1)
    -> { Time.new(2000, 1, 1, 0, 0, 0, 86400) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the utc_offset argument is greater than or equal to 10e9" do
    -> { Time.new(2000, 1, 1, 0, 0, 0, 1000000000) }.should raise_error(ArgumentError)
  end
end

describe "Time.new with a timezone argument" do
  it "returns a Time in the timezone" do
    zone = TimeSpecs::Timezone.new(offset: (5*3600+30*60))
    time = Time.new(2000, 1, 1, 12, 0, 0, zone)

    time.zone.should == zone
    time.utc_offset.should == 5*3600+30*60
    time.wday.should == 6
    time.yday.should == 1
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
      }.should raise_error(NoMethodError, /undefined method [`']name' for/)
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

  ruby_version_is '3.1' do # https://bugs.ruby-lang.org/issues/17485
    describe ":in keyword argument" do
      it "could be UTC offset as a String in '+HH:MM or '-HH:MM' format" do
        time = Time.new(2000, 1, 1, 12, 0, 0, in: "+05:00")

        time.utc_offset.should == 5*60*60
        time.zone.should == nil

        time = Time.new(2000, 1, 1, 12, 0, 0, in: "-09:00")

        time.utc_offset.should == -9*60*60
        time.zone.should == nil
      end

      it "could be UTC offset as a number of seconds" do
        time = Time.new(2000, 1, 1, 12, 0, 0, in: 5*60*60)

        time.utc_offset.should == 5*60*60
        time.zone.should == nil

        time = Time.new(2000, 1, 1, 12, 0, 0, in: -9*60*60)

        time.utc_offset.should == -9*60*60
        time.zone.should == nil
      end

      it "returns a Time with UTC offset specified as a single letter military timezone" do
        Time.new(2000, 1, 1, 0, 0, 0, in: "W").utc_offset.should == 3600 * -10
      end

      it "could be a timezone object" do
        zone = TimeSpecs::TimezoneWithName.new(name: "Asia/Colombo")
        time = Time.new(2000, 1, 1, 12, 0, 0, in: zone)

        time.utc_offset.should == 5*3600+30*60
        time.zone.should == zone

        zone = TimeSpecs::TimezoneWithName.new(name: "PST")
        time = Time.new(2000, 1, 1, 12, 0, 0, in: zone)

        time.utc_offset.should == -9*60*60
        time.zone.should == zone
      end

      it "allows omitting minor arguments" do
        Time.new(2000, 1, 1, 12, 1, 1, in: "+05:00").should == Time.new(2000, 1, 1, 12, 1, 1, "+05:00")
        Time.new(2000, 1, 1, 12, 1, in: "+05:00").should == Time.new(2000, 1, 1, 12, 1, 0, "+05:00")
        Time.new(2000, 1, 1, 12, in: "+05:00").should == Time.new(2000, 1, 1, 12, 0, 0, "+05:00")
        Time.new(2000, 1, 1, in: "+05:00").should == Time.new(2000, 1, 1, 0, 0, 0, "+05:00")
        Time.new(2000, 1, in: "+05:00").should == Time.new(2000, 1, 1, 0, 0, 0, "+05:00")
        Time.new(2000, in: "+05:00").should == Time.new(2000, 1, 1, 0, 0, 0, "+05:00")
        Time.new(in: "+05:00").should be_close(Time.now.getlocal("+05:00"), TIME_TOLERANCE)
      end

      it "converts to a provided timezone if all the positional arguments are omitted" do
        Time.new(in: "+05:00").utc_offset.should == 5*3600
      end

      it "raises ArgumentError if format is invalid" do
        -> { Time.new(2000, 1, 1, 12, 0, 0, in: "+09:99") }.should raise_error(ArgumentError)
        -> { Time.new(2000, 1, 1, 12, 0, 0, in: "ABC") }.should raise_error(ArgumentError)
      end

      it "raises ArgumentError if two offset arguments are given" do
        -> {
          Time.new(2000, 1, 1, 12, 0, 0, "+05:00", in: "+05:00")
        }.should raise_error(ArgumentError, "timezone argument given as positional and keyword arguments")
      end
    end
  end

  ruby_version_is "3.2" do
    describe "Time.new with a String argument" do
      it "parses an ISO-8601 like format" do
        t = Time.utc(2020, 12, 24, 15, 56, 17)

        Time.new("2020-12-24T15:56:17Z").should == t
        Time.new("2020-12-25 00:56:17 +09:00").should == t
        Time.new("2020-12-25 00:57:47 +09:01:30").should == t
        Time.new("2020-12-25 00:56:17 +0900").should == t
        Time.new("2020-12-25 00:57:47 +090130").should == t
        Time.new("2020-12-25T00:56:17+09:00").should == t
      end

      it "accepts precision keyword argument and truncates specified digits of sub-second part" do
        Time.new("2021-12-25 00:00:00.123456789876 +09:00").subsec.should == 0.123456789r
        Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: nil).subsec.should == 0.123456789876r
        Time.new("2021-12-25 00:00:00 +09:00", precision: 0).subsec.should == 0
        Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: -1).subsec.should == 0.123456789876r
      end

      it "returns Time in local timezone if not provided in the String argument" do
        Time.new("2021-12-25 00:00:00").zone.should == Time.new(2021, 12, 25).zone
        Time.new("2021-12-25 00:00:00").utc_offset.should == Time.new(2021, 12, 25).utc_offset
      end

      it "returns Time in timezone specified in the String argument" do
        Time.new("2021-12-25 00:00:00 +05:00").to_s.should == "2021-12-25 00:00:00 +0500"
      end

      it "returns Time in timezone specified in the String argument even if the in keyword argument provided" do
        Time.new("2021-12-25 00:00:00 +09:00", in: "-01:00").to_s.should == "2021-12-25 00:00:00 +0900"
      end

      it "returns Time in timezone specified with in keyword argument if timezone isn't provided in the String argument" do
        Time.new("2021-12-25 00:00:00", in: "-01:00").to_s.should == "2021-12-25 00:00:00 -0100"
      end

      it "converts precision keyword argument into Integer if is not nil" do
        obj = Object.new
        def obj.to_int; 3; end

        Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: 1.2).subsec.should == 0.1r
        Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: obj).subsec.should == 0.123r
        Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: 3r).subsec.should == 0.123r
      end

      ruby_version_is ""..."3.3" do
        it "raise TypeError is can't convert precision keyword argument into Integer" do
          -> {
            Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: "")
          }.should raise_error(TypeError, "no implicit conversion from string")
        end
      end

      ruby_version_is "3.3" do
        it "raise TypeError is can't convert precision keyword argument into Integer" do
          -> {
            Time.new("2021-12-25 00:00:00.123456789876 +09:00", precision: "")
          }.should raise_error(TypeError, "no implicit conversion of String into Integer")
        end
      end

      it "raises ArgumentError if part of time string is missing" do
        -> {
          Time.new("2020-12-25 00:56 +09:00")
        }.should raise_error(ArgumentError, "missing sec part: 00:56 ")

        -> {
          Time.new("2020-12-25 00 +09:00")
        }.should raise_error(ArgumentError, "missing min part: 00 ")
      end

      it "raises ArgumentError if subsecond is missing after dot" do
        -> {
          Time.new("2020-12-25 00:56:17. +0900")
        }.should raise_error(ArgumentError, "subsecond expected after dot: 00:56:17. ")
      end

      it "raises ArgumentError if String argument is not in the supported format" do
        -> {
          Time.new("021-12-25 00:00:00.123456 +09:00")
        }.should raise_error(ArgumentError, "year must be 4 or more digits: 021")

        -> {
          Time.new("2020-012-25 00:56:17 +0900")
        }.should raise_error(ArgumentError, /\Atwo digits mon is expected after [`']-': -012-25 00:\z/)

        -> {
          Time.new("2020-2-25 00:56:17 +0900")
        }.should raise_error(ArgumentError, /\Atwo digits mon is expected after [`']-': -2-25 00:56\z/)

        -> {
          Time.new("2020-12-215 00:56:17 +0900")
        }.should raise_error(ArgumentError, /\Atwo digits mday is expected after [`']-': -215 00:56:\z/)

        -> {
          Time.new("2020-12-25 000:56:17 +0900")
        }.should raise_error(ArgumentError, "two digits hour is expected:  000:56:17 ")

        -> {
          Time.new("2020-12-25 0:56:17 +0900")
        }.should raise_error(ArgumentError, "two digits hour is expected:  0:56:17 +0")

        -> {
          Time.new("2020-12-25 00:516:17 +0900")
        }.should raise_error(ArgumentError, /\Atwo digits min is expected after [`']:': :516:17 \+09\z/)

        -> {
          Time.new("2020-12-25 00:6:17 +0900")
        }.should raise_error(ArgumentError, /\Atwo digits min is expected after [`']:': :6:17 \+0900\z/)

        -> {
          Time.new("2020-12-25 00:56:137 +0900")
        }.should raise_error(ArgumentError, /\Atwo digits sec is expected after [`']:': :137 \+0900\z/)

        -> {
          Time.new("2020-12-25 00:56:7 +0900")
        }.should raise_error(ArgumentError, /\Atwo digits sec is expected after [`']:': :7 \+0900\z/)

        -> {
          Time.new("2020-12-25 00:56. +0900")
        }.should raise_error(ArgumentError, "fraction min is not supported: 00:56.")

        -> {
          Time.new("2020-12-25 00. +0900")
        }.should raise_error(ArgumentError, "fraction hour is not supported: 00.")
      end

      it "raises ArgumentError if date/time parts values are not valid" do
        -> {
          Time.new("2020-13-25 00:56:17 +09:00")
        }.should raise_error(ArgumentError, "mon out of range")

        -> {
          Time.new("2020-12-32 00:56:17 +09:00")
        }.should raise_error(ArgumentError, "mday out of range")

        -> {
          Time.new("2020-12-25 25:56:17 +09:00")
        }.should raise_error(ArgumentError, "hour out of range")

        -> {
          Time.new("2020-12-25 00:61:17 +09:00")
        }.should raise_error(ArgumentError, "min out of range")

        -> {
          Time.new("2020-12-25 00:56:61 +09:00")
        }.should raise_error(ArgumentError, "sec out of range")

        -> {
          Time.new("2020-12-25 00:56:17 +23:59:60")
        }.should raise_error(ArgumentError, "utc_offset out of range")

        -> {
          Time.new("2020-12-25 00:56:17 +24:00")
        }.should raise_error(ArgumentError, "utc_offset out of range")

        -> {
          Time.new("2020-12-25 00:56:17 +23:61")
        }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +23:61')
      end

      it "raises ArgumentError if string has not ascii-compatible encoding" do
        -> {
          Time.new("2021-11-31 00:00:60 +09:00".encode("utf-32le"))
        }.should raise_error(ArgumentError, "time string should have ASCII compatible encoding")
      end
    end
  end
end
