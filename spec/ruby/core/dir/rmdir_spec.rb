require_relative '../../spec_helper'

describe "Dir.rmdir" do
  it "is an alias of Dir.delete" do
    Dir.method(:rmdir).should == Dir.method(:delete)
  end
end
