# frozen_string_literal: true

require_relative "helper"
require "open3"

class TestProjectSanity < Gem::TestCase
  def test_manifest_is_up_to_date
    pend unless File.exist?(File.expand_path('../../Rakefile', __dir__))

    _, status = Open3.capture2e("rake check_manifest")

    assert status.success?, "Expected Manifest.txt to be up to date, but it's not. Run `rake update_manifest` to sync it."
  end

  def test_require_rubygems_package
    err, status = Open3.capture2e(*ruby_with_rubygems_in_load_path, "--disable-gems", "-e", "require \"rubygems/package\"")

    assert status.success?, err
  end
end
