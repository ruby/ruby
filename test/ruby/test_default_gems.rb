# frozen_string_literal: false
require 'rubygems'

class TestDefaultGems < Test::Unit::TestCase

  def test_validate_gemspec
    srcdir = File.expand_path('../../..', __FILE__)
    specs = 0
    Dir.chdir(srcdir) do
      unless system("git", "rev-parse", %i[out err]=>IO::NULL)
        omit "git not found"
      end
      Dir.glob("#{srcdir}/{lib,ext}/**/*.gemspec").map do |src|
        specs += 1
        assert_nothing_raised do
          raise("invalid spec in #{src}") unless Gem::Specification.load(src)
        end
      end
    end
    assert specs > 0, "gemspecs not found"
  end

end
