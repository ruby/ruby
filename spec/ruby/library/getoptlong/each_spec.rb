require_relative '../../spec_helper'
require 'getoptlong'

describe "GetoptLong#each" do
  it "is an alias of GetoptLong#each_option" do
    GetoptLong.instance_method(:each).should == GetoptLong.instance_method(:each_option)
  end
end
