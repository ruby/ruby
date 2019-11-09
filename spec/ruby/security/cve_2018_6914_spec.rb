require_relative '../spec_helper'

require 'tempfile'
require 'tmpdir'

describe "CVE-2018-6914 is resisted by" do
  before :each do
    @tmpdir = ENV['TMPDIR']
    @dir = tmp("CVE-2018-6914")
    Dir.mkdir(@dir, 0700)
    ENV['TMPDIR'] = @dir

    # Make sure that ENV["TMPDIR"] is used by Dir.tmpdir
    # https://github.com/ruby/ruby/runs/294462511#step:10:134
    10.times do
      break if Dir.tmpdir == File.expand_path(@dir)
      sleep 0.1
    end

    @debug_print = ->(actual) {
      PP.pp({
        actual: actual,
        absolute: File.absolute_path(actual),
        dir: @dir,
        pwd: Dir.pwd,
        tmpdir: @tmpdir,
        Dir_tmpdir: Dir.tmpdir,
        TMPDIR: ENV['TMPDIR'],
        stat: File.stat(@dir),
      }, STDERR)
    }

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
    @debug_print.call(actual)
    File.absolute_path(actual).should.start_with?(@dir)
  end

  it "Tempfile.new by deleting separators" do
    @tempfile = Tempfile.new('../foo')
    actual = @tempfile.path
    @debug_print.call(actual)
    File.absolute_path(actual).should.start_with?(@dir)
  end

  it "Tempfile.create by deleting separators" do
    actual = Tempfile.create('../foo') do |t|
      t.path
    end
    @debug_print.call(actual)
    File.absolute_path(actual).should.start_with?(@dir)
  end

  it "Dir.mktmpdir by deleting separators" do
    actual = Dir.mktmpdir('../foo') do |path|
      path
    end
    @debug_print.call(actual)
    File.absolute_path(actual).should.start_with?(@dir)
  end

  it "Dir.mktmpdir with an array by deleting separators" do
    actual = Dir.mktmpdir(['../', 'foo']) do |path|
      path
    end
    @debug_print.call(actual)
    File.absolute_path(actual).should.start_with?(@dir)
  end
end
