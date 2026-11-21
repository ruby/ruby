require_relative '../../spec_helper'

describe 'String#dedup' do
  it "is an alias of String#-@" do
    String.instance_method(:dedup).should == String.instance_method(:-@)
  end
end
