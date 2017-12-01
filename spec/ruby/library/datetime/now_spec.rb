require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "DateTime.now" do
  it "creates an instance of DateTime" do
    DateTime.now.should be_an_instance_of(DateTime)
  end

  it "sets the current date" do
    (DateTime.now - Date.today).to_f.should be_close(0.0, 2.0)
  end

  it "sets the current time" do
    dt = DateTime.now
    now = Time.now
    (dt.to_time - now).should be_close(0.0, 10.0)
  end

  it "grabs the local timezone" do
    with_timezone("PDT", -8) do
      dt = DateTime.now
      dt.zone.should == "-08:00"
    end
  end
end
