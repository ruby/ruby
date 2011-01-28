######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/test_case'
require 'rubygems/gem_path_searcher'

class Gem::GemPathSearcher
  attr_accessor :gemspecs
  attr_accessor :lib_dirs
end

class TestGemGemPathSearcher < Gem::TestCase

  def setup
    super

    @foo1 = quick_gem 'foo', '0.1' do |s|
      s.require_paths << 'lib2'
      s.files << 'lib/foo.rb'
    end

    path = File.join 'gems', @foo1.full_name, 'lib', 'foo.rb'
    write_file(path) { |fp| fp.puts "# #{path}" }

    @foo2 = quick_gem 'foo', '0.2'
    @bar1 = quick_gem 'bar', '0.1'
    @bar2 = quick_gem 'bar', '0.2'
    @nrp = quick_gem 'nil_require_paths', '0.1'
    @nrp.require_paths = nil


    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    Gem.source_index = util_setup_spec_fetcher @foo1, @foo2, @bar1, @bar2

    @gps = Gem::GemPathSearcher.new
  end

  def test_find
    assert_equal @foo1, @gps.find('foo')
  end

  def test_find_all
    assert_equal [@foo1], @gps.find_all('foo')
  end

  def test_init_gemspecs
    assert_equal [@bar2, @bar1, @foo2, @foo1], @gps.init_gemspecs
  end

  def test_lib_dirs_for
    lib_dirs = @gps.lib_dirs_for(@foo1)
    expected = File.join @gemhome, 'gems', @foo1.full_name, '{lib,lib2}'

    assert_equal expected, lib_dirs
  end

  def test_lib_dirs_for_nil_require_paths
    assert_nil @gps.lib_dirs_for(@nrp)
  end

  def test_matching_file_eh
    refute @gps.matching_file?(@foo1, 'bar')
    assert @gps.matching_file?(@foo1, 'foo')
  end

  def test_matching_files
    assert_equal [], @gps.matching_files(@foo1, 'bar')

    expected = File.join @foo1.full_gem_path, 'lib', 'foo.rb'

    assert_equal [expected], @gps.matching_files(@foo1, 'foo')
  end

  def test_matching_files_nil_require_paths
    assert_empty @gps.matching_files(@nrp, 'foo')
  end

end

