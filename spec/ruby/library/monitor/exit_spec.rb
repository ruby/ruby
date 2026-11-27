require_relative '../../spec_helper'
require 'monitor'

describe "Monitor#exit" do
  it "raises ThreadError when monitor is not entered" do
    m = Monitor.new

    -> { m.exit }.should.raise(ThreadError)
  end
end
