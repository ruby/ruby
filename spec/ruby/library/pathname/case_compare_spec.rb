require_relative '../../spec_helper'
require 'pathname'

describe "Pathname#===" do
  it "is an alias of Pathname#==" do
    Pathname.instance_method(:===).should == Pathname.instance_method(:==)
  end
end
