require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir.home" do
  before :each do
    @home = ENV['HOME']
    ENV['HOME'] = "/rubyspec_home"
  end

  after :each do
    ENV['HOME'] = @home
  end

  describe "when called without arguments" do
    it "returns the current user's home directory, reading $HOME first" do
      Dir.home.should == "/rubyspec_home"
    end

    it "returns a non-frozen string" do
      Dir.home.should_not.frozen?
    end

    it "returns a string with the filesystem encoding" do
      Dir.home.encoding.should == Encoding.find("filesystem")
    end

    platform_is_not :windows do
      it "works even if HOME is unset" do
        ENV.delete('HOME')
        Dir.home.should.start_with?('/')
        Dir.home.encoding.should == Encoding.find("filesystem")
      end
    end

    platform_is :windows do
      ruby_version_is "3.2" do
        it "returns the home directory with forward slashs and as UTF-8" do
          ENV['HOME'] = "C:\\rubyspäc\\home"
          home = Dir.home
          home.should == "C:/rubyspäc/home"
          home.encoding.should == Encoding::UTF_8
        end
      end

      it "retrieves the directory from HOME, USERPROFILE, HOMEDRIVE/HOMEPATH and the WinAPI in that order" do
        old_dirs = [ENV.delete('HOME'), ENV.delete('USERPROFILE'), ENV.delete('HOMEDRIVE'), ENV.delete('HOMEPATH')]

        Dir.home.should == old_dirs[1].gsub("\\", "/")
        ENV['HOMEDRIVE'] = "C:"
        ENV['HOMEPATH'] = "\\rubyspec\\home1"
        Dir.home.should == "C:/rubyspec/home1"
        ENV['USERPROFILE'] = "C:\\rubyspec\\home2"
        # https://bugs.ruby-lang.org/issues/19244
        # Dir.home.should == "C:/rubyspec/home2"
        ENV['HOME'] = "C:\\rubyspec\\home3"
        Dir.home.should == "C:/rubyspec/home3"
      ensure
        ENV['HOME'], ENV['USERPROFILE'], ENV['HOMEDRIVE'], ENV['HOMEPATH'] = *old_dirs
      end
    end
  end

  describe "when called with the current user name" do
    platform_is :solaris do
      it "returns the named user's home directory from the user database" do
        Dir.home(ENV['USER']).should == `getent passwd #{ENV['USER']}|cut -d: -f6`.chomp
      end
    end

    platform_is_not :windows, :solaris, :android, :wasi do
      it "returns the named user's home directory, from the user database" do
        Dir.home(ENV['USER']).should == `echo ~#{ENV['USER']}`.chomp
      end
    end

    it "returns a non-frozen string" do
      Dir.home(ENV['USER']).should_not.frozen?
    end

    it "returns a string with the filesystem encoding" do
      Dir.home(ENV['USER']).encoding.should == Encoding.find("filesystem")
    end
  end

  it "raises an ArgumentError if the named user doesn't exist" do
    -> { Dir.home('geuw2n288dh2k') }.should raise_error(ArgumentError)
  end
end
