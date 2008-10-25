#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/builder'

class TestGemBuilder < RubyGemTestCase

  def test_build
    builder = Gem::Builder.new quick_gem('a')

    use_ui @ui do
      Dir.chdir @tempdir do
        builder.build
      end
    end

    assert_match %r|Successfully built RubyGem\n  Name: a|, @ui.output
  end

  def test_build_validates
    builder = Gem::Builder.new Gem::Specification.new

    assert_raises Gem::InvalidSpecificationException do
      builder.build
    end
  end

end

