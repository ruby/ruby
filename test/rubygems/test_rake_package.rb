# frozen_string_literal: true

require "rubygems/test_case"
require "open3"

class TestRakePackage < Minitest::Test

  def test_builds_ok
    output, status = Open3.capture2e("rake package")

    assert_equal true, status.success?, "Expected `rake package` to work, but got errors: #{output}"
  end

end
