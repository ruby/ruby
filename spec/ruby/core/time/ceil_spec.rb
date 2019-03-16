require_relative '../../spec_helper'

ruby_version_is "2.7" do
  describe "Time#ceil" do
    before do
      @time = Time.utc(2010, 3, 30, 5, 43, "25.0123456789".to_r)
    end

    it "defaults to ceiling to 0 places" do
      @time.ceil.should == Time.utc(2010, 3, 30, 5, 43, 26.to_r)
    end

    it "ceils to 0 decimal places with an explicit argument" do
      @time.ceil(0).should == Time.utc(2010, 3, 30, 5, 43, 26.to_r)
    end

    it "ceils to 2 decimal places with an explicit argument" do
      @time.ceil(2).should == Time.utc(2010, 3, 30, 5, 43, "25.02".to_r)
    end

    it "ceils to 4 decimal places with an explicit argument" do
      @time.ceil(4).should == Time.utc(2010, 3, 30, 5, 43, "25.0124".to_r)
    end

    it "ceils to 7 decimal places with an explicit argument" do
      @time.ceil(7).should == Time.utc(2010, 3, 30, 5, 43, "25.0123457".to_r)
    end

    it "returns an instance of Time, even if #ceil is called on a subclass" do
      subclass = Class.new(Time)
      instance = subclass.at(0)
      instance.class.should equal subclass
      instance.ceil.should be_an_instance_of(Time)
    end

    it "copies own timezone to the returning value" do
      @time.zone.should == @time.ceil.zone

      with_timezone "JST-9" do
        time = Time.at 0, 1
        time.zone.should == time.ceil.zone
      end
    end
  end
end
