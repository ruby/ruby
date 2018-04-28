require_relative '../../spec_helper'

describe "Time.at" do
  describe "passed Numeric" do
    it "returns a Time object representing the given number of Integer seconds since 1970-01-01 00:00:00 UTC" do
      Time.at(1184027924).getgm.asctime.should == "Tue Jul 10 00:38:44 2007"
    end

    it "returns a Time object representing the given number of Float seconds since 1970-01-01 00:00:00 UTC" do
      t = Time.at(10.5)
      t.usec.should == 500000.0
      t.should_not == Time.at(10)
    end

    it "returns a non-UTC Time" do
      Time.at(1184027924).utc?.should == false
    end

    it "returns a subclass instance on a Time subclass" do
      c = Class.new(Time)
      t = c.at(0)
      t.should be_an_instance_of(c)
    end

    it "roundtrips a Rational produced by #to_r" do
      t = Time.now()
      t2 = Time.at(t.to_r)

      t2.should == t
      t2.usec.should == t.usec
      t2.nsec.should == t.nsec
    end

    describe "passed BigDecimal" do
      it "doesn't round input value" do
        require 'bigdecimal'
        Time.at(BigDecimal('1.1')).to_f.should == 1.1
      end
    end
  end

  describe "passed Time" do
    it "creates a new time object with the value given by time" do
      t = Time.now
      Time.at(t).inspect.should == t.inspect
    end

    it "creates a dup time object with the value given by time" do
      t1 = Time.new
      t2 = Time.at(t1)
      t1.should_not equal t2
    end

    it "returns a UTC time if the argument is UTC" do
      t = Time.now.getgm
      Time.at(t).utc?.should == true
    end

    it "returns a non-UTC time if the argument is non-UTC" do
      t = Time.now
      Time.at(t).utc?.should == false
    end

    it "returns a subclass instance" do
      c = Class.new(Time)
      t = c.at(Time.now)
      t.should be_an_instance_of(c)
    end
  end

  describe "passed non-Time, non-Numeric" do
    it "raises a TypeError with a String argument" do
      lambda { Time.at("0") }.should raise_error(TypeError)
    end

    it "raises a TypeError with a nil argument" do
      lambda { Time.at(nil) }.should raise_error(TypeError)
    end

    describe "with an argument that responds to #to_int" do
      it "coerces using #to_int" do
        o = mock('integer')
        o.should_receive(:to_int).and_return(0)
        Time.at(o).should == Time.at(0)
      end
    end

    describe "with an argument that responds to #to_r" do
      it "coerces using #to_r" do
        o = mock_numeric('rational')
        o.should_receive(:to_r).and_return(Rational(5, 2))
        Time.at(o).should == Time.at(Rational(5, 2))
      end
    end
  end

  describe "passed [Integer, Numeric]" do
    it "returns a Time object representing the given number of seconds and Integer microseconds since 1970-01-01 00:00:00 UTC" do
      t = Time.at(10, 500000)
      t.tv_sec.should == 10
      t.tv_usec.should == 500000
    end

    it "returns a Time object representing the given number of seconds and Float microseconds since 1970-01-01 00:00:00 UTC" do
      t = Time.at(10, 500.500)
      t.tv_sec.should == 10
      t.tv_nsec.should == 500500
    end
  end

  describe "with a second argument that responds to #to_int" do
    it "coerces using #to_int" do
      o = mock('integer')
      o.should_receive(:to_int).and_return(10)
      Time.at(0, o).should == Time.at(0, 10)
    end
  end

  describe "with a second argument that responds to #to_r" do
    it "coerces using #to_r" do
      o = mock_numeric('rational')
      o.should_receive(:to_r).and_return(Rational(5, 2))
      Time.at(0, o).should == Time.at(0, Rational(5, 2))
    end
  end

  describe "passed [Integer, nil]" do
    it "raises a TypeError" do
      lambda { Time.at(0, nil) }.should raise_error(TypeError)
    end
  end

  describe "passed [Integer, String]" do
    it "raises a TypeError" do
      lambda { Time.at(0, "0") }.should raise_error(TypeError)
    end
  end

  describe "passed [Time, Integer]" do
    # #8173
    it "raises a TypeError" do
      lambda { Time.at(Time.now, 500000) }.should raise_error(TypeError)
    end
  end

  ruby_version_is "2.5" do
    describe "passed [Time, Numeric, format]" do
      context ":nanosecond format" do
        it "traits second argument as nanoseconds" do
          Time.at(0, 123456789, :nanosecond).nsec.should == 123456789
        end
      end

      context ":nsec format" do
        it "traits second argument as nanoseconds" do
          Time.at(0, 123456789, :nsec).nsec.should == 123456789
        end
      end

      context ":microsecond format" do
        it "traits second argument as microseconds" do
          Time.at(0, 123456, :microsecond).nsec.should == 123456000
        end
      end

      context ":usec format" do
        it "traits second argument as microseconds" do
          Time.at(0, 123456, :usec).nsec.should == 123456000
        end
      end

      context ":millisecond format" do
        it "traits second argument as milliseconds" do
          Time.at(0, 123, :millisecond).nsec.should == 123000000
        end
      end

      context "not supported format" do
        it "raises ArgumentError" do
          ->() { Time.at(0, 123456, 2) }.should raise_error(ArgumentError)
          ->() { Time.at(0, 123456, nil) }.should raise_error(ArgumentError)
          ->() { Time.at(0, 123456, :invalid) }.should raise_error(ArgumentError)
        end

        it "does not try to convert format to Symbol with #to_sym" do
          format = "usec"
          format.should_not_receive(:to_sym)
          -> () { Time.at(0, 123456, format) }.should raise_error(ArgumentError)
        end
      end

      it "supports Float second argument" do
        Time.at(0, 123456789.500, :nanosecond).nsec.should == 123456789
        Time.at(0, 123456789.500, :nsec).nsec.should == 123456789
        Time.at(0, 123456.500, :microsecond).nsec.should == 123456500
        Time.at(0, 123456.500, :usec).nsec.should == 123456500
        Time.at(0, 123.500, :millisecond).nsec.should == 123500000
      end
    end
  end
end
