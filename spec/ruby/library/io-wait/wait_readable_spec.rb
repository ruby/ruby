require_relative '../../spec_helper'

ruby_version_is ''...'3.2' do
  require 'io/wait'
end

describe "IO#wait_readable" do
  before :each do
    @io = File.new(__FILE__ )
  end

  after :each do
    @io.close
  end

  it "waits for the IO to become readable with no timeout" do
    @io.wait_readable.should == @io
  end

  it "waits for the IO to become readable with the given timeout" do
    @io.wait_readable(1).should == @io
  end

  it "waits for the IO to become readable with the given large timeout" do
    @io.wait_readable(365 * 24 * 60 * 60).should == @io
  end
end
