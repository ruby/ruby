require_relative '../../spec_helper'
require_relative '../../shared/time/yday'

describe "Time#yday" do
  it "returns an integer representing the day of the year, 1..366" do
    with_timezone("UTC") do
      Time.at(9999999).yday.should == 116
    end
  end

  it_behaves_like :time_yday, -> year, month, day { Time.new(year, month, day).yday }
end
