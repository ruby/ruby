require 'rubygems/test_case'
require 'rubygems/simple_gem'

class TestGemPackageOld < Gem::TestCase

  def setup
    super

    open 'old_format.gem', 'wb' do |io|
      io.write SIMPLE_GEM
    end

    @package = Gem::Package::Old.new 'old_format.gem'
    @destination = File.join @tempdir, 'extract'
  end

  def test_contents
    assert_equal %w[lib/foo.rb lib/test.rb lib/test/wow.rb], @package.contents
  end

  def test_extract_files
    @package.extract_files @destination

    extracted = File.join @destination, 'lib/foo.rb'
    assert_path_exists extracted

    mask = 0100644 & (~File.umask)

    assert_equal mask, File.stat(extracted).mode unless win_platform?
  end

  def test_spec
    assert_equal 'testing', @package.spec.name
  end

end

