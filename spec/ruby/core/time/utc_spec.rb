require_relative '../../spec_helper'
require_relative 'shared/time_params'

describe "Time#utc?" do
  it "returns true only if time represents a time in UTC (GMT)" do
    Time.now.utc?.should == false
    Time.now.utc.utc?.should == true
  end

  it "treats time as UTC what was created in different ways" do
    Time.now.utc.utc?.should == true
    Time.now.utc.utc?.should == true
    Time.now.getgm.utc?.should == true
    Time.now.getutc.utc?.should == true
    Time.utc(2022).utc?.should == true
  end

  it "does treat time with 'UTC' offset as UTC" do
    Time.new(2022, 1, 1, 0, 0, 0, "UTC").utc?.should == true
    Time.now.localtime("UTC").utc?.should == true
    Time.at(Time.now, in: 'UTC').utc?.should == true

    Time.new(2022, 1, 1, 0, 0, 0, in: "UTC").utc?.should == true
    Time.now(in: "UTC").utc?.should == true
  end

  it "does treat time with Z offset as UTC" do
    Time.new(2022, 1, 1, 0, 0, 0, "Z").utc?.should == true
    Time.now.localtime("Z").utc?.should == true
    Time.at(Time.now, in: 'Z').utc?.should == true

    Time.new(2022, 1, 1, 0, 0, 0, in: "Z").utc?.should == true
    Time.now(in: "Z").utc?.should == true
  end

  it "does treat time with -00:00 offset as UTC" do
    Time.new(2022, 1, 1, 0, 0, 0, "-00:00").utc?.should == true
    Time.now.localtime("-00:00").utc?.should == true
    Time.at(Time.now, in: '-00:00').utc?.should == true
  end

  it "does not treat time with +00:00 offset as UTC" do
    Time.new(2022, 1, 1, 0, 0, 0, "+00:00").utc?.should == false
    Time.now.localtime("+00:00").utc?.should == false
    Time.at(Time.now, in: "+00:00").utc?.should == false
  end

  it "does not treat time with 0 offset as UTC" do
    Time.new(2022, 1, 1, 0, 0, 0, 0).utc?.should == false
    Time.now.localtime(0).utc?.should == false
    Time.at(Time.now, in: 0).utc?.should == false
  end
end

describe "Time.utc" do
  it_behaves_like :time_params, :utc
  it_behaves_like :time_params_10_arg, :utc
  it_behaves_like :time_params_microseconds, :utc

  it "creates a time based on given values, interpreted as UTC (GMT)" do
    Time.utc(2000,"jan",1,20,15,1).inspect.should == "2000-01-01 20:15:01 UTC"
  end

  it "creates a time based on given C-style gmtime arguments, interpreted as UTC (GMT)" do
    time = Time.utc(1, 15, 20, 1, 1, 2000, :ignored, :ignored, :ignored, :ignored)
    time.inspect.should == "2000-01-01 20:15:01 UTC"
  end

  it "interprets pre-Gregorian reform dates using Gregorian proleptic calendar" do
    Time.utc(1582, 10, 4, 12).to_i.should == -12220200000 # 2299150j
  end

  it "interprets Julian-Gregorian gap dates using Gregorian proleptic calendar" do
    Time.utc(1582, 10, 14, 12).to_i.should == -12219336000 # 2299160j
  end

  it "interprets post-Gregorian reform dates using Gregorian calendar" do
    Time.utc(1582, 10, 15, 12).to_i.should == -12219249600 # 2299161j
  end

  it "handles fractional usec close to rounding limit" do
    time = Time.utc(2000, 1, 1, 12, 30, 0, 9999r/10000)

    time.usec.should == 0
    time.nsec.should == 999
  end

  guard -> {
    with_timezone 'right/UTC' do
      (Time.utc(1972, 6, 30, 23, 59, 59) + 1).sec == 60
    end
  } do
    it "handles real leap seconds in zone 'right/UTC'" do
      with_timezone 'right/UTC' do
        time = Time.utc(1972, 6, 30, 23, 59, 60)

        time.sec.should == 60
        time.min.should == 59
        time.hour.should == 23
        time.day.should == 30
        time.month.should == 6
      end
    end
  end

  it "handles bad leap seconds by carrying values forward" do
    with_timezone 'UTC' do
      time = Time.utc(2017, 7, 5, 23, 59, 60)
      time.sec.should == 0
      time.min.should == 0
      time.hour.should == 0
      time.day.should == 6
      time.month.should == 7
    end
  end

  it "handles a value of 60 for seconds by carrying values forward in zone 'UTC'" do
    with_timezone 'UTC' do
      time = Time.utc(1972, 6, 30, 23, 59, 60)

      time.sec.should == 0
      time.min.should == 0
      time.hour.should == 0
      time.day.should == 1
      time.month.should == 7
    end
  end
end

describe "Time#utc" do
  it "converts self to UTC, modifying the receiver" do
    # Testing with America/Regina here because it doesn't have DST.
    with_timezone("CST", -6) do
      t = Time.local(2007, 1, 9, 6, 0, 0)
      t.utc
      # Time#== compensates for time zones, so check all parts separately
      t.year.should == 2007
      t.month.should == 1
      t.mday.should == 9
      t.hour.should == 12
      t.min.should == 0
      t.sec.should == 0
      t.zone.should == "UTC"
    end
  end

  it "returns self" do
    with_timezone("CST", -6) do
      t = Time.local(2007, 1, 9, 12, 0, 0)
      t.utc.should.equal?(t)
    end
  end

  describe "on a frozen time" do
    it "does not raise an error if already in UTC" do
      time = Time.gm(2007, 1, 9, 12, 0, 0)
      time.freeze
      time.utc.should.equal?(time)
    end

    it "raises a FrozenError if the time is not UTC" do
      with_timezone("CST", -6) do
        time = Time.now
        time.freeze
        -> { time.utc }.should.raise(FrozenError)
      end
    end
  end
end
