######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require "test/rubygems/gemutilities"
require "test/rubygems/simple_gem"
require 'rubygems/format'

class TestGemFormat < RubyGemTestCase

  def setup
    super

    @simple_gem = SIMPLE_GEM
  end

  def test_class_from_file_by_path
    util_make_gems

    gems = Dir[File.join(@gemhome, 'cache', '*.gem')]

    names = [@a1, @a2, @a3a, @a_evil9, @b2, @c1_2, @pl1].map do |spec|
      spec.original_name
    end

    gems_n_names = gems.sort.zip names

    gems_n_names.each do |gemfile, name|
      spec = Gem::Format.from_file_by_path(gemfile).spec

      assert_equal name, spec.original_name
    end
  end

  def test_class_from_file_by_path_empty
    util_make_gems

    empty_gem = File.join @tempdir, 'empty.gem'
    FileUtils.touch empty_gem

    assert_nil Gem::Format.from_file_by_path(empty_gem)
  end

  def test_class_from_file_by_path_nonexistent
    assert_raises Gem::Exception do
      Gem::Format.from_file_by_path '/nonexistent'
    end
  end

  def test_class_from_io_garbled
    e = assert_raises Gem::Package::FormatError do
      # subtly bogus input
      Gem::Format.from_io(StringIO.new(@simple_gem.upcase))
    end

    assert_equal 'No metadata found!', e.message

    e = assert_raises Gem::Package::FormatError do
      # Totally bogus input
      Gem::Format.from_io(StringIO.new(@simple_gem.reverse))
    end

    assert_equal 'No metadata found!', e.message

    e = assert_raises Gem::Package::FormatError do
      # This was intentionally screws up YAML parsing.
      Gem::Format.from_io(StringIO.new(@simple_gem.gsub(/:/, "boom")))
    end

    assert_equal 'No metadata found!', e.message
  end

end

