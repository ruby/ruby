require_relative '../../spec_helper'

describe "Dir.unlink" do
  it "is an alias of Dir.delete" do
    Dir.method(:unlink).should == Dir.method(:delete)
  end
end
