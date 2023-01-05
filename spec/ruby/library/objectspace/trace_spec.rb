require_relative '../../spec_helper'

ruby_version_is "3.1" do
  describe 'require "objspace/trace"' do
    it "shows object allocation sites" do
      file = fixture(__FILE__ , "trace.rb")
      ruby_exe(file, args: "2>&1").lines(chomp: true).should == [
        "objspace/trace is enabled",
        "\"foo\" @ #{file}:2",
        "\"bar\" @ #{file}:3",
        "42"
      ]
    end
  end
end
