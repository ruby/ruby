#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require File.join(File.expand_path(File.dirname(__FILE__)), 'simple_gem')
require 'rubygems/format'

class TestGemFormat < RubyGemTestCase

  def setup
    super

    @simple_gem = SIMPLE_GEM
  end

  def test_from_file_by_path
    util_make_gems

    gems = Dir[File.join(@gemhome, 'cache', '*.gem')]

    names = [@a1, @a2, @a_evil9, @b2, @c1_2, @pl1].map do |spec|
      spec.original_name
    end

    gems_n_names = gems.sort.zip names

    gems_n_names.each do |gemfile, name|
      spec = Gem::Format.from_file_by_path(gemfile).spec

      assert_equal name, spec.original_name
    end
  end

  def test_from_file_by_path_nonexistent
    assert_raises Gem::Exception do
      Gem::Format.from_file_by_path '/nonexistent'
    end
  end

  def test_from_io_garbled
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

