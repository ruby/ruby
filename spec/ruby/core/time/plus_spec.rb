require_relative '../../spec_helper'

describe "Time#+" do
  it "increments the time by the specified amount" do
    (Time.at(0) + 100).should == Time.at(100)
  end

  it "is a commutative operator" do
    (Time.at(1.1) + 0.9).should == Time.at(0.9) + 1.1
  end

  it "adds a negative Float" do
    t = Time.at(100) + -1.3
    t.usec.should == 699999
    t.to_i.should == 98
  end

  it "raises a TypeError if given argument is a coercible String" do
    lambda { Time.now + "1" }.should raise_error(TypeError)
    lambda { Time.now + "0.1" }.should raise_error(TypeError)
    lambda { Time.now + "1/3" }.should raise_error(TypeError)
  end

  it "increments the time by the specified amount as rational numbers" do
    (Time.at(Rational(11, 10)) + Rational(9, 10)).should == Time.at(2)
  end

  it "accepts arguments that can be coerced into Rational" do
    (obj = mock_numeric('10')).should_receive(:to_r).and_return(Rational(10))
    (Time.at(100) + obj).should == Time.at(110)
  end

  it "raises TypeError on argument that can't be coerced into Rational" do
    lambda { Time.now + Object.new }.should raise_error(TypeError)
    lambda { Time.now + "stuff" }.should raise_error(TypeError)
  end

  it "returns a UTC time if self is UTC" do
    (Time.utc(2012) + 10).utc?.should == true
  end

  it "returns a non-UTC time if self is non-UTC" do
    (Time.local(2012) + 10).utc?.should == false
  end

  it "returns a time with the same fixed offset as self" do
    (Time.new(2012, 1, 1, 0, 0, 0, 3600) + 10).utc_offset.should == 3600
  end

  ruby_version_is "2.6" do
    it "returns a time with the same timezone as self" do
      zone = mock("timezone")
      zone.should_receive(:local_to_utc).and_return(Time.utc(2012, 1, 1, 6, 30, 0))
      zone.should_receive(:utc_to_local).and_return(Time.utc(2012, 1, 1, 12, 0, 10))
      t = Time.new(2012, 1, 1, 12, 0, 0, zone) + 10
      t.zone.should == zone
      t.utc_offset.should == 19800
      t.to_a[0, 6].should == [10, 0, 12, 1, 1, 2012]
      t.should == Time.utc(2012, 1, 1, 6, 30, 10)
    end
  end

  it "does not return a subclass instance" do
    c = Class.new(Time)
    x = c.now + 1
    x.should be_an_instance_of(Time)
  end

  it "raises TypeError on Time argument" do
    lambda { Time.now + Time.now }.should raise_error(TypeError)
  end

  it "raises TypeError on nil argument" do
    lambda { Time.now + nil }.should raise_error(TypeError)
  end

  #see [ruby-dev:38446]
  it "tracks microseconds" do
    time = Time.at(0)
    time += Rational(123_456, 1_000_000)
    time.usec.should == 123_456
    time += Rational(654_321, 1_000_000)
    time.usec.should == 777_777
  end

  it "tracks nanoseconds" do
    time = Time.at(0)
    time += Rational(123_456_789, 1_000_000_000)
    time.nsec.should == 123_456_789
    time += Rational(876_543_210, 1_000_000_000)
    time.nsec.should == 999_999_999
  end

  it "maintains precision" do
    t = Time.at(0) + Rational(8_999_999_999_999_999, 1_000_000_000_000_000)
    t.should_not == Time.at(9)
  end

  it "maintains microseconds precision" do
    time = Time.at(0) + Rational(8_999_999_999_999_999, 1_000_000_000_000_000)
    time.usec.should == 999_999
  end

  it "maintains nanoseconds precision" do
    time = Time.at(0) + Rational(8_999_999_999_999_999, 1_000_000_000_000_000)
    time.nsec.should == 999_999_999
  end

  it "maintains subseconds precision" do
    time = Time.at(0) + Rational(8_999_999_999_999_999, 1_000_000_000_000_000)
    time.subsec.should == Rational(999_999_999_999_999, 1_000_000_000_000_000)
  end
end
