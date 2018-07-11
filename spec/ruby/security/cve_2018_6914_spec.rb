require_relative '../spec_helper'

require 'tempfile'

describe "CVE-2018-6914 is resisted by" do
  before :all do
    @traversal_path = Array.new(Dir.pwd.split('/').count, '..').join('/') + Dir.pwd + '/'
    @traversal_path.delete!(':') if /mswin|mingw/ =~ RUBY_PLATFORM
  end

  it "Tempfile.open by deleting separators" do
    begin
      expect = Dir.glob(@traversal_path + '*').count
      t = Tempfile.open([@traversal_path, 'foo'])
      actual = Dir.glob(@traversal_path + '*').count
      actual.should == expect
    ensure
      t.close!
    end
  end

  it "Tempfile.new by deleting separators" do
    begin
      expect = Dir.glob(@traversal_path + '*').count
      t = Tempfile.new(@traversal_path + 'foo')
      actual = Dir.glob(@traversal_path + '*').count
      actual.should == expect
    ensure
      t.close!
    end
  end

  it "Tempfile.create by deleting separators" do
    expect = Dir.glob(@traversal_path + '*').count
    Tempfile.create(@traversal_path + 'foo') do
      actual = Dir.glob(@traversal_path + '*').count
      actual.should == expect
    end
  end

  it "Dir.mktmpdir by deleting separators" do
    expect = Dir.glob(@traversal_path + '*').count
    Dir.mktmpdir(@traversal_path + 'foo') do
      actual = Dir.glob(@traversal_path + '*').count
      actual.should == expect
    end
  end

  it "Dir.mktmpdir with an array by deleting separators" do
    expect = Dir.glob(@traversal_path + '*').count
    Dir.mktmpdir([@traversal_path, 'foo']) do
      actual = Dir.glob(@traversal_path + '*').count
      actual.should == expect
    end
  end
end
