require_relative '../../spec_helper'
require 'ostruct'

describe "OpenStruct#initialize" do
  it "is private" do
    OpenStruct.private_instance_methods(false).should.include?(:initialize)
  end
end
