#
#
#

$:.unshift File.dirname(__FILE__)

require 'fileutils'
require 'test/unit'
require 'fileasserts'


class TestNoWrite < Test::Unit::TestCase

  include FileUtils::NoWrite

  SRC  = 'data/src'
  COPY = 'data/copy'

  def setup
    system 'rm -rf data; mkdir data'
    system 'rm -rf tmp; mkdir tmp'
    File.open( SRC,  'w' ) {|f| f.puts 'dummy' }
    File.open( COPY, 'w' ) {|f| f.puts 'dummy' }
  end

  def teardown
    system 'rm -rf data tmp'
  end

  def test_cp
    cp SRC, 'tmp/cp'
    check 'tmp/cp'
  end

  def test_mv
    mv SRC, 'tmp/mv'
    check 'tmp/mv'
  end

  def check( dest )
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
