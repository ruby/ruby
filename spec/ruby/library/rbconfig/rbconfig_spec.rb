require_relative '../../spec_helper'
require 'rbconfig'

describe 'RbConfig::CONFIG' do
  it 'values are all strings' do
    RbConfig::CONFIG.each do |k, v|
      k.should be_kind_of String
      v.should be_kind_of String
    end
  end

  # These directories have no meanings before the installation.
  guard -> { RbConfig::TOPDIR } do
    it "['rubylibdir'] returns the directory containing Ruby standard libraries" do
      rubylibdir = RbConfig::CONFIG['rubylibdir']
      File.directory?(rubylibdir).should == true
      File.should.exist?("#{rubylibdir}/fileutils.rb")
    end

    it "['archdir'] returns the directory containing standard libraries C extensions" do
      archdir = RbConfig::CONFIG['archdir']
      File.directory?(archdir).should == true
      File.should.exist?("#{archdir}/etc.#{RbConfig::CONFIG['DLEXT']}")
    end
  end

  it "contains no frozen strings even with --enable-frozen-string-literal" do
    ruby_exe(<<-RUBY, options: '--enable-frozen-string-literal').should == "Done\n"
      require 'rbconfig'
      RbConfig::CONFIG.each do |k, v|
        if v.frozen?
          puts "\#{k} Failure"
        end
      end
      puts 'Done'
    RUBY
  end
end

describe "RbConfig::TOPDIR" do
  it "either returns nil (if not installed) or the prefix" do
    if RbConfig::TOPDIR
      RbConfig::TOPDIR.should == RbConfig::CONFIG["prefix"]
    else
      RbConfig::TOPDIR.should == nil
    end
  end
end
