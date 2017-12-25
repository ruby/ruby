require File.expand_path('../../../spec_helper', __FILE__)
require 'pathname'

ruby_version_is '2.4' do
  describe 'Pathname#empty?' do
    before :all  do
      @file = tmp 'new_file_path_name.txt'
      touch @file
      @dir = tmp 'new_directory_path_name'
      Dir.mkdir @dir
    end

    after :all do
      rm_r @file
      rm_r @dir
    end

    it 'returns true when file is not empty' do
      Pathname.new(__FILE__).empty?.should be_false
    end

    it 'returns false when the directory is not empty' do
      Pathname.new(__dir__).empty?.should be_false
    end

    it 'return true when file is empty' do
      Pathname.new(@file).empty?.should be_true
    end

    it 'returns true when directory is empty' do
      Pathname.new(@dir).empty?.should be_true
    end
  end
end
