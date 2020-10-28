require_relative '../spec_helper'

require 'tempfile'
require 'tmpdir'

describe "CVE-2018-6914 is resisted by" do
  before :each do
    @tmpdir = ENV['TMPDIR']
    @dir = tmp("CVE-2018-6914")
    Dir.mkdir(@dir, 0700)
    ENV['TMPDIR'] = @dir
    @dir << '/'

    @tempfile = nil
  end

  after :each do
    ENV['TMPDIR'] = @tmpdir
    @tempfile.close! if @tempfile
    rm_r @dir
  end

  it "Tempfile.open by deleting separators" do
    @tempfile = Tempfile.open(['../', 'foo'])
    actual = @tempfile.path
    File.absolute_path(actual).should.start_with?(@dir)
  end

  it "Tempfile.new by deleting separators" do
    @tempfile = Tempfile.new('../foo')
    actual = @tempfile.path
    File.absolute_path(actual).should.start_with?(@dir)
  end

  it "Tempfile.create by deleting separators" do
    actual = Tempfile.create('../foo') do |t|
      t.path
    end
    File.absolute_path(actual).should.start_with?(@dir)
  end

  it "Dir.mktmpdir by deleting separators" do
    actual = Dir.mktmpdir('../foo') do |path|
      path
    end
    File.absolute_path(actual).should.start_with?(@dir)
  end

  it "Dir.mktmpdir with an array by deleting separators" do
    actual = Dir.mktmpdir(['../', 'foo']) do |path|
      path
    end
    File.absolute_path(actual).should.start_with?(@dir)
  end
end
