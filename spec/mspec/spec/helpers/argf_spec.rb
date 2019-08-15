require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

describe Object, "#argf" do
  before :each do
    @saved_argv = ARGV.dup
    @argv = [__FILE__]
  end

  it "sets @argf to an instance of ARGF.class with the given argv" do
    argf @argv do
      @argf.should be_an_instance_of ARGF.class
      @argf.filename.should == @argv.first
    end
    @argf.should be_nil
  end

  it "does not alter ARGV nor ARGF" do
    argf @argv do
    end
    ARGV.should == @saved_argv
    ARGF.argv.should == @saved_argv
  end

  it "does not close STDIN" do
    argf ['-'] do
    end
    STDIN.should_not be_closed
  end

  it "disallows nested calls" do
    argf @argv do
      lambda { argf @argv }.should raise_error
    end
  end
end
