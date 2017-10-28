require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date.today" do
  it "returns a Date object" do
    Date.today.should be_kind_of Date
  end

  it "sets Date object to the current date" do
    today = Date.today
    now = Time.now
    (now - today.to_time).should be_close(0.0, 24 * 60 * 60)
  end
end
