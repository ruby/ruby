require_relative '../../spec_helper'

describe "Time#gmt?" do
  it "returns true if time represents a time in UTC (GMT)" do
    Time.now.should_not.gmt?
    Time.now.gmtime.should.gmt?
  end
end
