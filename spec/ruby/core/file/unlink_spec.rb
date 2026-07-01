require_relative '../../spec_helper'

describe "File.unlink" do
  it "is an alias of File.delete" do
    File.method(:unlink).should == File.method(:delete)
  end
end
