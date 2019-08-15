# frozen_string_literal: true

require "rubygems/test_case"
require "open3"

class TestRakePackage < Minitest::Test

  def test_builds_ok
    skip unless File.exist?(File.expand_path("../../../Rakefile", __FILE__))

    output, status = Open3.capture2e("rake package")

    assert_equal true, status.success?, <<~MSG.chomp
      Expected `rake package` to work, but got errors:

      ```
      #{output}
      ```

      If you have added or removed files, make sure you run `rake update_manifest` to update the `Manifest.txt` accordingly
    MSG

    FileUtils.rm_f "pkg"
  end

end
