# frozen_string_literal: false
require 'rubygems'

class TestDefaultGems < Test::Unit::TestCase
  def self.load(file)
    code = File.read(file, mode: "r:UTF-8:-", &:read)

    # - `git ls-files` is useless under ruby's repository
    # - `2>/dev/null` works only on Unix-like platforms
    code.gsub!(/`git.*?`/, '""')

    eval(code, binding, file)
  end

  def test_validate_gemspec
    srcdir = File.expand_path('../../..', __FILE__)
    specs = 0
    Dir.chdir(srcdir) do
      all_assertions_foreach(nil, *Dir["{lib,ext}/**/*.gemspec"]) do |src|
        specs += 1
        assert_kind_of(Gem::Specification, self.class.load(src), "invalid spec in #{src}")
      end
    end
    assert_operator specs, :>, 0, "gemspecs not found"
  end

end
