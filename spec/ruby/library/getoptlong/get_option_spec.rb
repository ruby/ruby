require_relative '../../spec_helper'
require 'getoptlong'

describe "GetoptLong#get_option" do
  it "is an alias of GetoptLong#get" do
    GetoptLong.instance_method(:get_option).should == GetoptLong.instance_method(:get)
  end
end
