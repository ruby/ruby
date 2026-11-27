require_relative '../../../spec_helper'

ruby_version_is "4.1" do
  describe "Ruby::SourceRange#inspect" do
    it "includes the absolute path and coordinates" do
      range = proc { 1 }.source_range

      range.inspect.should == "#<Ruby::SourceRange #{range.absolute_path}:(#{range.start_line},#{range.start_column})-(#{range.end_line},#{range.end_column})>"
    end

    it "uses path when absolute_path is nil" do
      range = eval('proc { 1 }', nil, "foo", 100).source_range

      range.absolute_path.should == nil
      range.inspect.should == "#<Ruby::SourceRange foo:(#{range.start_line},#{range.start_column})-(#{range.end_line},#{range.end_column})>"
    end
  end
end
