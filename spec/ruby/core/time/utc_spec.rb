require_relative '../../spec_helper'
require_relative 'shared/gm'
require_relative 'shared/gmtime'
require_relative 'shared/time_params'

describe "Time#utc?" do
  it "returns true if time represents a time in UTC (GMT)" do
    Time.now.utc?.should == false
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
