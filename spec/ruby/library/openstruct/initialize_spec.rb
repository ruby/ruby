require_relative '../../spec_helper'
require 'ostruct'

describe "OpenStruct#initialize" do
  it "is private" do
    OpenStruct.should have_private_instance_method(:initialize)
  end
end
