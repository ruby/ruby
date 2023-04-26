require_relative '../../spec_helper'

describe "Time#zone" do
  platform_is_not :windows do
    it "returns the time zone used for time" do
      with_timezone("America/New_York") do
        Time.new(2001, 1, 1, 0, 0, 0).zone.should == "EST"
        Time.new(2001, 7, 1, 0, 0, 0).zone.should == "EDT"
        %w[EST EDT].should include Time.now.zone
      end
    end
  end

  it "returns nil for a Time with a fixed offset" do
    Time.new(2001, 1, 1, 0, 0, 0, "+05:00").zone.should == nil
  end

  platform_is_not :windows do
    it "returns the correct timezone for a local time" do
      t = Time.new(2005, 2, 27, 22, 50, 0, -3600)

      with_timezone("America/New_York") do
        t.getlocal.zone.should == "EST"
      end
    end
  end

  it "returns nil when getting the local time with a fixed offset" do
    t = Time.new(2005, 2, 27, 22, 50, 0, -3600)

    with_timezone("America/New_York") do
      t.getlocal("+05:00").zone.should be_nil
    end
  end

  describe "Encoding.default_internal is set" do
    before :each do
      @encoding = Encoding.default_internal
      Encoding.default_internal = Encoding::UTF_8
    end

    after :each do
      Encoding.default_internal = @encoding
    end

    it "returns an ASCII string" do
      t = Time.new(2005, 2, 27, 22, 50, 0, -3600)

      with_timezone("America/New_York") do
        t.getlocal.zone.encoding.should == Encoding::US_ASCII
      end
    end

    it "doesn't raise errors for a Time with a fixed offset" do
      Time.new(2001, 1, 1, 0, 0, 0, "+05:00").zone.should == nil
    end
  end

  it "returns UTC when called on a UTC time" do
    Time.now.utc.zone.should == "UTC"
    Time.now.gmtime.zone.should == "UTC"
    Time.now.getgm.zone.should == "UTC"
    Time.now.getutc.zone.should == "UTC"
    Time.utc(2022).zone.should == "UTC"
    Time.new(2022, 1, 1, 0, 0, 0, "UTC").zone.should == "UTC"
    Time.new(2022, 1, 1, 0, 0, 0, "Z").zone.should == "UTC"
    Time.now.localtime("UTC").zone.should == "UTC"
    Time.now.localtime("Z").zone.should == "UTC"
    Time.at(Time.now, in: 'UTC').zone.should == "UTC"
    Time.at(Time.now, in: 'Z').zone.should == "UTC"

    ruby_version_is "3.1" do
      Time.new(2022, 1, 1, 0, 0, 0, "-00:00").zone.should == "UTC"
      Time.now.localtime("-00:00").zone.should == "UTC"
      Time.at(Time.now, in: '-00:00').zone.should == "UTC"
    end

    ruby_version_is "3.1" do
      Time.new(2022, 1, 1, 0, 0, 0, in: "UTC").zone.should == "UTC"
      Time.new(2022, 1, 1, 0, 0, 0, in: "Z").zone.should == "UTC"

      Time.now(in: 'UTC').zone.should == "UTC"
      Time.now(in: 'Z').zone.should == "UTC"

      Time.at(Time.now, in: 'UTC').zone.should == "UTC"
      Time.at(Time.now, in: 'Z').zone.should == "UTC"
    end
  end

  platform_is_not :aix, :windows do
    it "defaults to UTC when bad zones given" do
      with_timezone("hello-foo") do
        Time.now.utc_offset.should == 0
      end
      with_timezone("1,2") do
        Time.now.utc_offset.should == 0
      end
      with_timezone("Sun,Fri,2") do
        Time.now.utc_offset.should == 0
      end
    end
  end

  platform_is :windows do
    # See https://bugs.ruby-lang.org/issues/13591#note-11
    it "defaults to UTC when bad zones given" do
      with_timezone("1,2") do
        Time.now.utc_offset.should == 0
      end
      with_timezone("12") do
        Time.now.utc_offset.should == 0
      end
    end
  end
end
