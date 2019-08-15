require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir#inspect" do
  before :each do
    @dir = Dir.new(Dir.getwd)
  end

  after :each do
    @dir.close
  end

  it "returns a String" do
    @dir.inspect.should be_an_instance_of(String)
  end

  it "includes the class name" do
    @dir.inspect.should =~ /Dir/
  end

  it "includes the directory name" do
    @dir.inspect.should include(Dir.getwd)
  end
end
