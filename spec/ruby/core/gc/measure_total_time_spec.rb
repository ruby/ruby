require_relative '../../spec_helper'

ruby_version_is "3.1" do
  describe "GC.measure_total_time" do
    before :each do
      @default = GC.measure_total_time
    end

    after :each do
      GC.measure_total_time = @default
    end

    it "can set and get a boolean value" do
      original = GC.measure_total_time
      GC.measure_total_time = !original
      GC.measure_total_time.should == !original
    end
  end
end
