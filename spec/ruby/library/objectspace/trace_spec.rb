require_relative '../../spec_helper'

describe 'require "objspace/trace"' do
  it "shows object allocation sites" do
    file = fixture(__FILE__ , "trace.rb")
    ruby_exe(file, args: "2>&1").lines(chomp: true).should == [
      "objspace/trace is enabled",
      "\"foo\" @ #{file}:3",
      "\"bar\" @ #{file}:4",
      "42"
    ]
  end
end
