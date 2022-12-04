# frozen_string_literal: true

require_relative "helper"
require "rubygems/validator"

class TestGemValidator < Gem::TestCase
  def setup
    super

    @validator = Gem::Validator.new
  end

  def test_alien
    @spec = quick_gem "a" do |s|
      s.files = %w[lib/a.rb lib/b.rb]
    end

    util_build_gem @spec

    FileUtils.rm    File.join(@spec.gem_dir, "lib/b.rb")
    FileUtils.touch File.join(@spec.gem_dir, "lib/c.rb")

    alien = @validator.alien "a"

    expected = {
      @spec.file_name => [
        Gem::Validator::ErrorData.new("lib/b.rb", "Missing file"),
        Gem::Validator::ErrorData.new("lib/c.rb", "Extra file"),
      ],
    }

    assert_equal expected, alien
  end

  def test_alien_default
    new_default_spec "c", 1, nil, "lib/c.rb"

    alien = @validator.alien "c"

    assert_empty alien
  end
end
