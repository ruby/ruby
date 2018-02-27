require File.expand_path('../../../spec_helper', __FILE__)

describe "Hash#clone" do
  it "copies instance variable but not the objects they refer to" do
    hash = { 'key' => 'value' }

    clone = hash.clone

    clone.should == hash
    clone.should_not equal hash
  end
end

