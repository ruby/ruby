require_relative '../../spec_helper'
require 'rbconfig'

describe 'RbConfig::CONFIG' do
  it 'values are all strings' do
    RbConfig::CONFIG.each do |k, v|
      k.should be_kind_of String
      v.should be_kind_of String
    end
  end

  it "['rubylibdir'] returns the directory containing Ruby standard libraries" do
    rubylibdir = RbConfig::CONFIG['rubylibdir']
    File.directory?(rubylibdir).should == true
    File.exist?("#{rubylibdir}/fileutils.rb").should == true
  end

  it "['archdir'] returns the directory containing standard libraries C extensions" do
    archdir = RbConfig::CONFIG['archdir']
    File.directory?(archdir).should == true
    File.exist?("#{archdir}/etc.#{RbConfig::CONFIG['DLEXT']}").should == true
  end
end
