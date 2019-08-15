require_relative '../spec_helper'

require 'tempfile'
require 'tmpdir'

describe "CVE-2018-6914 is resisted by" do
  before :each do
    @dir = tmp("CVE-2018-6914")
    Dir.mkdir(@dir)
    touch "#{@dir}/bar"

    @traversal_path = Array.new(@dir.count('/'), '..').join('/') + @dir + '/'
    @traversal_path.delete!(':') if platform_is(:windows)

    @tempfile = nil
  end

  after :each do
    @tempfile.close! if @tempfile
    rm_r @dir
  end

  it "Tempfile.open by deleting separators" do
    expect = Dir.glob(@traversal_path + '*').size
    @tempfile = Tempfile.open([@traversal_path, 'foo'])
    actual = Dir.glob(@traversal_path + '*').size
    actual.should == expect
  end

  it "Tempfile.new by deleting separators" do
    expect = Dir.glob(@traversal_path + '*').size
    @tempfile = Tempfile.new(@traversal_path + 'foo')
    actual = Dir.glob(@traversal_path + '*').size
    actual.should == expect
  end

  it "Tempfile.create by deleting separators" do
    expect = Dir.glob(@traversal_path + '*').size
    Tempfile.create(@traversal_path + 'foo') do
      actual = Dir.glob(@traversal_path + '*').size
      actual.should == expect
    end
  end

  it "Dir.mktmpdir by deleting separators" do
    expect = Dir.glob(@traversal_path + '*').size
    Dir.mktmpdir(@traversal_path + 'foo') do
      actual = Dir.glob(@traversal_path + '*').size
      actual.should == expect
    end
  end

  it "Dir.mktmpdir with an array by deleting separators" do
    expect = Dir.glob(@traversal_path + '*').size
    Dir.mktmpdir([@traversal_path, 'foo']) do
      actual = Dir.glob(@traversal_path + '*').size
      actual.should == expect
    end
  end
end
