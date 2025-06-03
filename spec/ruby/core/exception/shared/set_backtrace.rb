require_relative '../fixtures/common'

describe :exception_set_backtrace, shared: true do
  it "accepts an Array of Strings" do
    err = @method.call(["unhappy"])
    err.backtrace.should == ["unhappy"]
  end

  it "allows the user to set the backtrace from a rescued exception" do
    bt  = ExceptionSpecs::Backtrace.backtrace
    err = @method.call(bt)
    err.backtrace.should == bt
  end

  ruby_version_is "3.4" do
    it "allows the user to set backtrace locations from a rescued exception" do
      bt_locations = ExceptionSpecs::Backtrace.backtrace_locations
      err = @method.call(bt_locations)
      err.backtrace_locations.size.should == bt_locations.size
      err.backtrace_locations.each_with_index do |loc, index|
        other_loc = bt_locations[index]

        loc.path.should == other_loc.path
        loc.label.should == other_loc.label
        loc.base_label.should == other_loc.base_label
        loc.lineno.should == other_loc.lineno
        loc.absolute_path.should == other_loc.absolute_path
        loc.to_s.should == other_loc.to_s
      end
      err.backtrace.size.should == err.backtrace_locations.size
    end
  end

  it "accepts an empty Array" do
    err = @method.call([])
    err.backtrace.should == []
  end

  it "accepts a String" do
    err = @method.call("unhappy")
    err.backtrace.should == ["unhappy"]
  end

  it "accepts nil" do
    err = @method.call(nil)
    err.backtrace.should be_nil
  end

  it "raises a TypeError when passed a Symbol" do
    -> { @method.call(:unhappy) }.should raise_error(TypeError)
  end

  it "raises a TypeError when the Array contains a Symbol" do
    -> { @method.call(["String", :unhappy]) }.should raise_error(TypeError)
  end

  it "raises a TypeError when the array contains nil" do
    -> { @method.call(["String", nil]) }.should raise_error(TypeError)
  end

  it "raises a TypeError when the argument is a nested array" do
    -> { @method.call(["String", ["String"]]) }.should raise_error(TypeError)
  end
end
