# $Id$

require 'fileutils'
require 'fileasserts'
require 'tmpdir'
require 'test/unit'

class TestFileUtilsNoWrite < Test::Unit::TestCase

  include FileUtils::NoWrite

  def test_visibility
    FileUtils::METHODS.each do |m|
      assert_equal true, FileUtils::NoWrite.respond_to?(m, true),
                   "FileUtils::NoWrite.#{m} is not defined"
      assert_equal true, FileUtils::NoWrite.respond_to?(m, false),
                   "FileUtils::NoWrite.#{m} is not public"
    end
    FileUtils::METHODS.each do |m|
      assert_equal true, respond_to?(m, true),
                   "FileUtils::NoWrite\##{m} is not defined"
      assert_equal true, FileUtils::NoWrite.private_method_defined?(m),
                   "FileUtils::NoWrite\##{m} is not private"
    end
  end

  def my_rm_rf(path)
    if File.exist?('/bin/rm')
      system %Q[/bin/rm -rf "#{path}"]
    else
      FileUtils.rm_rf path
    end
  end

  SRC  = 'data/src'
  COPY = 'data/copy'

  def setup
    @prevdir = Dir.pwd
    tmproot = "#{Dir.tmpdir}/fileutils.rb.#{$$}"
    Dir.mkdir tmproot unless File.directory?(tmproot)
    Dir.chdir tmproot
    my_rm_rf 'data'; Dir.mkdir 'data'
    my_rm_rf 'tmp'; Dir.mkdir 'tmp'
    File.open(SRC,  'w') {|f| f.puts 'dummy' }
    File.open(COPY, 'w') {|f| f.puts 'dummy' }
  end

  def teardown
    tmproot = Dir.pwd
    Dir.chdir @prevdir
    my_rm_rf tmproot
  end

  def test_cp
    cp SRC, 'tmp/cp'
    check 'tmp/cp'
  end

  def test_mv
    mv SRC, 'tmp/mv'
    check 'tmp/mv'
  end

  def check(dest)
    assert_file_not_exist dest
    assert_file_exist SRC
    assert_same_file SRC, COPY
  end

  def test_rm
    rm SRC
    assert_file_exist SRC
    assert_same_file SRC, COPY
  end

  def test_rm_f
    rm_f SRC
    assert_file_exist SRC
    assert_same_file SRC, COPY
  end

  def test_rm_rf
    rm_rf SRC
    assert_file_exist SRC
    assert_same_file SRC, COPY
  end

  def test_mkdir
    mkdir 'dir'
    assert_file_not_exist 'dir'
  end

  def test_mkdir_p
    mkdir 'dir/dir/dir'
    assert_file_not_exist 'dir'
  end

end
