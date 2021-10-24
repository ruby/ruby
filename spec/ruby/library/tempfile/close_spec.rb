require_relative '../../spec_helper'
require 'tempfile'

describe "Tempfile#close when passed no argument or [false]" do
  before :each do
    @tempfile = Tempfile.new("specs", tmp(""))
  end

  after :each do
    @tempfile.close!
  end

  it "closes self" do
    @tempfile.close
    @tempfile.closed?.should be_true
  end

  it "does not unlink self" do
    path = @tempfile.path
    @tempfile.close
    File.should.exist?(path)
  end
end

describe "Tempfile#close when passed [true]" do
  before :each do
    @tempfile = Tempfile.new("specs", tmp(""))
  end

  it "closes self" do
    @tempfile.close(true)
    @tempfile.closed?.should be_true
  end

  it "unlinks self" do
    path = @tempfile.path
    @tempfile.close(true)
    File.should_not.exist?(path)
  end
end

describe "Tempfile#close!" do
  before :each do
    @tempfile = Tempfile.new("specs", tmp(""))
  end

  it "closes self" do
    @tempfile.close!
    @tempfile.closed?.should be_true
  end

  it "unlinks self" do
    path =  @tempfile.path
    @tempfile.close!
    File.should_not.exist?(path)
  end
end
