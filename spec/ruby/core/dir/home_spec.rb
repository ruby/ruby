require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir.home" do
  it "returns the current user's home directory as a string if called without arguments" do
    home_directory = ENV['HOME']
    platform_is :windows do
      unless home_directory
        home_directory = ENV['HOMEDRIVE'] + ENV['HOMEPATH']
      end
      home_directory = home_directory.tr('\\', '/').chomp('/')
    end

    Dir.home.should == home_directory
  end

  platform_is :solaris do
    it "returns the named user's home directory, from the user database, as a string if called with an argument" do
      Dir.home(ENV['USER']).should == `getent passwd #{ENV['USER']}|cut -d: -f6`.chomp
    end
  end

  platform_is_not :windows, :solaris do
    it "returns the named user's home directory, from the user database, as a string if called with an argument" do
      Dir.home(ENV['USER']).should == `echo ~#{ENV['USER']}`.chomp
    end
  end

  it "raises an ArgumentError if the named user doesn't exist" do
    lambda { Dir.home('geuw2n288dh2k') }.should raise_error(ArgumentError)
  end
end
