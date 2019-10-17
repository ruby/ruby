require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

describe Object, "#tmp" do
  before :all do
    @dir = "#{File.expand_path(Dir.pwd)}/rubyspec_temp"
  end

  it "returns a name relative to the current working directory" do
    tmp("test.txt").should == "#{@dir}/#{SPEC_TEMP_UNIQUIFIER}-test.txt"
  end

  it "returns a 'unique' name on repeated calls" do
    a = tmp("text.txt")
    b = tmp("text.txt")
    a.should_not == b
  end

  it "does not 'uniquify' the name if requested not to" do
    tmp("test.txt", false).should == "#{@dir}/test.txt"
  end

  it "returns the name of the temporary directory when passed an empty string" do
    tmp("").should == "#{@dir}/"
  end
end
