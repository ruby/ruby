# frozen_string_literal: true

require_relative "test_helper"

class VersionTest < Test::Unit::TestCase
  def test_version_is_set
    refute_nil YARP::VERSION
  end
end
