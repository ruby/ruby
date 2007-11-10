require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/gem_path_searcher'

class Gem::GemPathSearcher
  attr_accessor :gemspecs
  attr_accessor :lib_dirs

  public :init_gemspecs
  public :matching_file
  public :lib_dirs_for
end

class TestGemGemPathSearcher < RubyGemTestCase

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

    Gem.source_index = util_setup_source_info_cache @foo1, @foo2, @bar1, @bar2

    @gps = Gem::GemPathSearcher.new
  end

  def test_find
    assert_equal @foo1, @gps.find('foo')
  end

  def test_init_gemspecs
    assert_equal [@bar2, @bar1, @foo2, @foo1], @gps.init_gemspecs
  end

  def test_lib_dirs_for
    lib_dirs = @gps.lib_dirs_for(@foo1)
    expected = File.join @gemhome, 'gems', @foo1.full_name, '{lib,lib2}'

    assert_equal expected, lib_dirs
  end

  def test_matching_file
    assert !@gps.matching_file(@foo1, 'bar')
    assert @gps.matching_file(@foo1, 'foo')
  end

end

