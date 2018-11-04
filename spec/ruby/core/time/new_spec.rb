require_relative '../../spec_helper'
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
    Time.new(2000, 1, 1, 0, 0, 0, 0).utc?.should == false
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
    lambda {
      Time.new(2000, 1, 1, 0, 0, 0, "+01:60")
    }.should raise_error(ArgumentError)
    lambda {
      Time.new(2000, 1, 1, 0, 0, 0, "+01:99")
    }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the String argument is not of the form (+|-)HH:MM" do
    lambda { Time.new(2000, 1, 1, 0, 0, 0, "3600") }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the hour value is greater than 23" do
    lambda { Time.new(2000, 1, 1, 0, 0, 0, "+24:00") }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the String argument is not in an ASCII-compatible encoding" do
    lambda { Time.new(2000, 1, 1, 0, 0, 0, "-04:10".encode("UTF-16LE")) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the argument represents a value less than or equal to -86400 seconds" do
    Time.new(2000, 1, 1, 0, 0, 0, -86400 + 1).utc_offset.should == (-86400 + 1)
    lambda { Time.new(2000, 1, 1, 0, 0, 0, -86400) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the argument represents a value greater than or equal to 86400 seconds" do
    Time.new(2000, 1, 1, 0, 0, 0, 86400 - 1).utc_offset.should == (86400 - 1)
    lambda { Time.new(2000, 1, 1, 0, 0, 0, 86400) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the seconds argument is negative" do
    lambda { Time.new(2000, 1, 1, 0, 0, -1) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError if the utc_offset argument is greater than or equal to 10e9" do
    lambda { Time.new(2000, 1, 1, 0, 0, 0, 1000000000) }.should raise_error(ArgumentError)
  end
end

ruby_version_is "2.6" do
  describe "Time.new with a timezone argument" do
    it "returns a Time correspoinding to UTC time returned by local_to_utc" do
      zone = TimeSpecs::Timezone.new("Asia/Colombo", "MMT", (5*3600+30*60))
      t = Time.new(2000, 1, 1, 12, 0, 0, zone)
      t.to_a[0, 6].should == [0, 0, 12, 1, 1, 2000]
      t.utc_offset.should == 19800
      t.zone.should == zone
    end
  end
end
