require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Time#getlocal" do
  it "returns a new time which is the local representation of time" do
    # Testing with America/Regina here because it doesn't have DST.
    with_timezone("CST", -6) do
      t = Time.gm(2007, 1, 9, 12, 0, 0)
      t.localtime.should == Time.local(2007, 1, 9, 6, 0, 0)
    end
  end

  it "returns a Time with UTC offset specified as an Integer number of seconds" do
    t = Time.gm(2007, 1, 9, 12, 0, 0).getlocal(3630)
    t.should == Time.new(2007, 1, 9, 13, 0, 30, 3630)
    t.utc_offset.should == 3630
  end

  platform_is_not :windows do
    it "returns a new time with the correct utc_offset according to the set timezone" do
      t = Time.new(2005, 2, 27, 22, 50, 0, -3600)
      t.utc_offset.should == -3600

      with_timezone("America/New_York") do
        t.getlocal.utc_offset.should == -18000
      end
    end
  end

  describe "with an argument that responds to #to_int" do
    it "coerces using #to_int" do
      o = mock('integer')
      o.should_receive(:to_int).and_return(3630)
      t = Time.gm(2007, 1, 9, 12, 0, 0).getlocal(o)
      t.should == Time.new(2007, 1, 9, 13, 0, 30, 3630)
      t.utc_offset.should == 3630
    end
  end

  it "returns a Time with a UTC offset of the specified number of Rational seconds" do
    t = Time.gm(2007, 1, 9, 12, 0, 0).getlocal(Rational(7201, 2))
    t.should == Time.new(2007, 1, 9, 13, 0, Rational(1, 2), Rational(7201, 2))
    t.utc_offset.should eql(Rational(7201, 2))
  end

  describe "with an argument that responds to #to_r" do
    it "coerces using #to_r" do
      o = mock_numeric('rational')
      o.should_receive(:to_r).and_return(Rational(7201, 2))
      t = Time.gm(2007, 1, 9, 12, 0, 0).getlocal(o)
      t.should == Time.new(2007, 1, 9, 13, 0, Rational(1, 2), Rational(7201, 2))
      t.utc_offset.should eql(Rational(7201, 2))
    end
  end

  it "returns a Time with a UTC offset specified as +HH:MM" do
    t = Time.gm(2007, 1, 9, 12, 0, 0).getlocal("+01:00")
    t.should == Time.new(2007, 1, 9, 13, 0, 0, 3600)
    t.utc_offset.should == 3600
  end

  it "returns a Time with a UTC offset specified as +HH:MM:SS" do
    t = Time.gm(2007, 1, 9, 12, 0, 0).getlocal("+01:00:01")
    t.should == Time.new(2007, 1, 9, 13, 0, 1, 3601)
    t.utc_offset.should == 3601
  end

  it "returns a Time with a UTC offset specified as -HH:MM" do
    t = Time.gm(2007, 1, 9, 12, 0, 0).getlocal("-01:00")
    t.should == Time.new(2007, 1, 9, 11, 0, 0, -3600)
    t.utc_offset.should == -3600
  end

  it "returns a Time with a UTC offset specified as -HH:MM:SS" do
    t = Time.gm(2007, 1, 9, 12, 0, 0).getlocal("-01:00:01")
    t.should == Time.new(2007, 1, 9, 10, 59, 59, -3601)
    t.utc_offset.should == -3601
  end

  describe "with an argument that responds to #to_str" do
    it "coerces using #to_str" do
      o = mock('string')
      o.should_receive(:to_str).and_return("+01:00")
      t = Time.gm(2007, 1, 9, 12, 0, 0).getlocal(o)
      t.should == Time.new(2007, 1, 9, 13, 0, 0, 3600)
      t.utc_offset.should == 3600
    end
  end

  it "raises ArgumentError if the String argument is not of the form (+|-)HH:MM" do
    t = Time.now
    -> { t.getlocal("3600") }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the String argument is not in an ASCII-compatible encoding" do
    t = Time.now
    -> { t.getlocal("-01:00".encode("UTF-16LE")) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the argument represents a value less than or equal to -86400 seconds" do
    t = Time.new
    t.getlocal(-86400 + 1).utc_offset.should == (-86400 + 1)
    -> { t.getlocal(-86400) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the argument represents a value greater than or equal to 86400 seconds" do
    t = Time.new
    t.getlocal(86400 - 1).utc_offset.should == (86400 - 1)
    -> { t.getlocal(86400) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if String argument and hours greater than 23" do
    ruby_version_is ""..."3.1" do
      -> { Time.now.getlocal("+24:00") }.should raise_error(ArgumentError, "utc_offset out of range")
      -> { Time.now.getlocal("+2400") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset')

      -> { Time.now.getlocal("+99:00") }.should raise_error(ArgumentError, "utc_offset out of range")
      -> { Time.now.getlocal("+9900") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset')
    end

    ruby_version_is "3.1" do
      -> { Time.now.getlocal("+24:00") }.should raise_error(ArgumentError, "utc_offset out of range")
      -> { Time.now.getlocal("+2400") }.should raise_error(ArgumentError, "utc_offset out of range")

      -> { Time.now.getlocal("+99:00") }.should raise_error(ArgumentError, "utc_offset out of range")
      -> { Time.now.getlocal("+9900") }.should raise_error(ArgumentError, "utc_offset out of range")
    end
  end

  it "raises ArgumentError if String argument and minutes greater than 59" do
    ruby_version_is ""..."3.1" do
      -> { Time.now.getlocal("+00:60") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset')
      -> { Time.now.getlocal("+0060") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset')

      -> { Time.now.getlocal("+00:99") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset')
      -> { Time.now.getlocal("+0099") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset')
    end

    ruby_version_is "3.1" do
      -> { Time.now.getlocal("+00:60") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +00:60')
      -> { Time.now.getlocal("+0060") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +0060')

      -> { Time.now.getlocal("+00:99") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +00:99')
      -> { Time.now.getlocal("+0099") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +0099')
    end
  end

  ruby_bug '#20797', ''...'3.4' do
    it "raises ArgumentError if String argument and seconds greater than 59" do
      -> { Time.now.getlocal("+00:00:60") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +00:00:60')
      -> { Time.now.getlocal("+000060") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +000060')

      -> { Time.now.getlocal("+00:00:99") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +00:00:99')
      -> { Time.now.getlocal("+000099") }.should raise_error(ArgumentError, '"+HH:MM", "-HH:MM", "UTC" or "A".."I","K".."Z" expected for utc_offset: +000099')
    end
  end

  describe "with a timezone argument" do
    it "returns a Time in the timezone" do
      zone = TimeSpecs::Timezone.new(offset: (5*3600+30*60))
      time = Time.utc(2000, 1, 1, 12, 0, 0).getlocal(zone)

      time.zone.should == zone
      time.utc_offset.should == 5*3600+30*60
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
        Time.utc(2000, 1, 1, 12, 0, 0).getlocal(zone).should be_kind_of(Time)
      }.should_not raise_error
    end

    it "raises TypeError if timezone does not implement #utc_to_local method" do
      zone = Object.new
      def zone.local_to_utc(time)
        time
      end

      -> {
        Time.utc(2000, 1, 1, 12, 0, 0).getlocal(zone)
      }.should raise_error(TypeError, /can't convert \w+ into an exact number/)
    end

    it "does not raise exception if timezone does not implement #local_to_utc method" do
      zone = Object.new
      def zone.utc_to_local(time)
        time
      end

      -> {
        Time.utc(2000, 1, 1, 12, 0, 0).getlocal(zone).should be_kind_of(Time)
      }.should_not raise_error
    end

    context "subject's class implements .find_timezone method" do
      it "calls .find_timezone to build a time object if passed zone name as a timezone argument" do
        time = TimeSpecs::TimeWithFindTimezone.utc(2000, 1, 1, 12, 0, 0).getlocal("Asia/Colombo")
        time.zone.should be_kind_of TimeSpecs::TimezoneWithName
        time.zone.name.should == "Asia/Colombo"

        time = TimeSpecs::TimeWithFindTimezone.utc(2000, 1, 1, 12, 0, 0).getlocal("some invalid zone name")
        time.zone.should be_kind_of TimeSpecs::TimezoneWithName
        time.zone.name.should == "some invalid zone name"
      end

      it "does not call .find_timezone if passed any not string/numeric/timezone timezone argument" do
        [Object.new, [], {}, :"some zone"].each do |zone|
          time = TimeSpecs::TimeWithFindTimezone.utc(2000, 1, 1, 12, 0, 0)

          -> {
            time.getlocal(zone)
          }.should raise_error(TypeError, /can't convert \w+ into an exact number/)
        end
      end
    end
  end
end
