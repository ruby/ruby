# frozen_string_literal: true

require_relative "helper"
require "open3"

class TestGemProjectSanity < Gem::TestCase
  def setup
  end

  def teardown
  end

  def test_manifest_is_up_to_date
    pend unless File.exist?("#{root}/Rakefile")
    rake = "#{root}/bin/rake"

    _, status = Open3.capture2e(rake, "check_manifest")

    unless status.success?
      original_contents = File.read("#{root}/Manifest.txt")

      # Update the manifest to see if it fixes the problem
      Open3.capture2e(rake, "update_manifest")

      out, status = Open3.capture2e(rake, "check_manifest")

      # If `rake update_manifest` fixed the problem, that was the original
      # issue, otherwise it was an unknown error, so print the error output
      if status.success?
        File.write("#{root}/Manifest.txt", original_contents)

        raise "Expected Manifest.txt to be up to date, but it's not. Run `bin/rake update_manifest` to sync it."
      else
        raise "There was an error running `bin/rake check_manifest`: #{out}"
      end
    end
  end

  def test_require_rubygems_package
    err, status = Open3.capture2e(*ruby_with_rubygems_in_load_path, "--disable-gems", "-e", "require \"rubygems/package\"")

    assert status.success?, err
  end

  private

  def root
    File.expand_path("../..", __dir__)
  end
end
