require_relative '../../spec_helper'
require_relative 'shared/gm'
require_relative 'shared/gmtime'
require_relative 'shared/time_params'

describe "Time#utc?" do
  it "returns true only if time represents a time in UTC (GMT)" do
    Time.now.utc?.should == false
    Time.now.utc.utc?.should == true
  end

  it "treats time as UTC what was created in different ways" do
    Time.now.utc.utc?.should == true
    Time.now.gmtime.utc?.should == true
    Time.now.getgm.utc?.should == true
    Time.now.getutc.utc?.should == true
    Time.utc(2022).utc?.should == true
  end

  it "does treat time with 'UTC' offset as UTC" do
    Time.new(2022, 1, 1, 0, 0, 0, "UTC").utc?.should == true
    Time.now.localtime("UTC").utc?.should == true
    Time.at(Time.now, in: 'UTC').utc?.should == true
  end

  it "does treat time with Z offset as UTC" do
    Time.new(2022, 1, 1, 0, 0, 0, "Z").utc?.should == true
    Time.now.localtime("Z").utc?.should == true
    Time.at(Time.now, in: 'Z').utc?.should == true
  end

  ruby_version_is "3.1" do
    it "does treat time with -00:00 offset as UTC" do
      Time.new(2022, 1, 1, 0, 0, 0, "-00:00").utc?.should == true
      Time.now.localtime("-00:00").utc?.should == true
      Time.at(Time.now, in: '-00:00').utc?.should == true
    end
  end

  it "does not treat time with +00:00 offset as UTC" do
    Time.new(2022, 1, 1, 0, 0, 0, "+00:00").utc?.should == false
  end

  it "does not treat time with 0 offset as UTC" do
    Time.new(2022, 1, 1, 0, 0, 0, 0).utc?.should == false
  end
end

describe "Time.utc" do
  it_behaves_like :time_gm, :utc
  it_behaves_like :time_params, :utc
  it_behaves_like :time_params_10_arg, :utc
  it_behaves_like :time_params_microseconds, :utc
end

describe "Time#utc" do
  it_behaves_like :time_gmtime, :utc
end
