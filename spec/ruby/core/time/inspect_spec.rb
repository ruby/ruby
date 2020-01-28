require_relative '../../spec_helper'
require_relative 'shared/inspect'

describe "Time#inspect" do
  it_behaves_like :inspect, :inspect

  ruby_version_is "2.7" do
    it "preserves milliseconds" do
      t = Time.utc(2007, 11, 1, 15, 25, 0, 123456)
      t.inspect.should == "2007-11-01 15:25:00.123456 UTC"
    end

    it "formats nanoseconds as a Rational" do
      t = Time.utc(2007, 11, 1, 15, 25, 0, 123456.789)
      t.nsec.should == 123456789
      t.strftime("%N").should == "123456789"

      t.inspect.should == "2007-11-01 15:25:00 8483885939586761/68719476736000000 UTC"
    end
  end
end
