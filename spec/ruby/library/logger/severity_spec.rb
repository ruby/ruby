require_relative '../../spec_helper'
require 'logger'

describe "Logger::Severity" do
  it "defines Logger severity constants" do
    Logger::DEBUG.should == 0
    Logger::INFO.should == 1
    Logger::WARN.should == 2
    Logger::ERROR.should == 3
    Logger::FATAL.should == 4
    Logger::UNKNOWN.should == 5
  end
end
