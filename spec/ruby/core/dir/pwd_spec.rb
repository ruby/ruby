# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir.pwd" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  before :each do
    @fs_encoding = Encoding.find('filesystem')
  end

  it "returns the current working directory" do
    pwd = Dir.pwd

    File.directory?(pwd).should == true

    # On ubuntu gutsy, for example, /bin/pwd does not
    # understand -P. With just `pwd -P`, /bin/pwd is run.

    # The following uses inode rather than file names to account for
    # case insensitive file systems like default OS/X file systems
    platform_is_not :windows do
      File.stat(pwd).ino.should == File.stat(`/bin/sh -c "pwd -P"`.chomp).ino
    end
    platform_is :windows do
      File.stat(pwd).ino.should == File.stat(File.expand_path(`cd`.chomp)).ino
    end
  end

  it "returns an absolute path" do
    pwd = Dir.pwd
    pwd.should == File.expand_path(pwd)
  end

  it "returns an absolute path even when chdir to a relative path" do
    Dir.chdir(".") do
      pwd = Dir.pwd
      File.directory?(pwd).should == true
      pwd.should == File.expand_path(pwd)
    end
  end

  it "returns a String with the filesystem encoding" do
    enc = Dir.pwd.encoding
    if @fs_encoding == Encoding::US_ASCII
      [Encoding::US_ASCII, Encoding::BINARY].should.include?(enc)
    else
      enc.should.equal?(@fs_encoding)
    end
  end
end

describe "Dir.pwd" do
  before :each do
    @name = tmp("あ").force_encoding('binary')
    @fs_encoding = Encoding.find('filesystem')
  end

  after :each do
    rm_r @name
  end

  platform_is_not :windows do
    it "correctly handles dirs with unicode characters in them" do
      Dir.mkdir @name
      Dir.chdir @name do
        if @fs_encoding == Encoding::UTF_8
          Dir.pwd.encoding.should == Encoding::UTF_8
        end
        Dir.pwd.force_encoding('binary').should == @name
      end
    end
  end
end
