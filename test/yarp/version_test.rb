# frozen_string_literal: true

require "test_helper"

class VersionTest < Test::Unit::TestCase
  test "version is set" do
    refute_nil YARP::VERSION
  end
end
