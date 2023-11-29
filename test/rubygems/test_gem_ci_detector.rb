# frozen_string_literal: true

require_relative "helper"
require "rubygems"

class TestCiDetector < Test::Unit::TestCase
  def test_ci?
    with_env("FOO" => "bar") { assert_equal(false, Gem::CIDetector.ci?) }
    with_env("CI" => "true") { assert_equal(true, Gem::CIDetector.ci?) }
    with_env("CONTINUOUS_INTEGRATION" => "1") { assert_equal(true, Gem::CIDetector.ci?) }
    with_env("RUN_ID" => "0", "TASKCLUSTER_ROOT_URL" => "2") do
      assert_equal(true, Gem::CIDetector.ci?)
    end
  end

  def test_ci_strings
    with_env("FOO" => "bar") { assert_empty(Gem::CIDetector.ci_strings) }
    with_env("TRAVIS" => "true") { assert_equal(["travis"], Gem::CIDetector.ci_strings) }
    with_env("CI" => "true", "CIRCLECI" => "true", "GITHUB_ACTIONS" => "true") do
      assert_equal(["ci", "circle", "github"], Gem::CIDetector.ci_strings)
    end
    with_env("CI" => "true", "CI_NAME" => "MYCI") do
      assert_equal(["ci", "myci"], Gem::CIDetector.ci_strings)
    end
    with_env("GITHUB_ACTIONS" => "true", "CI_NAME" => "github") do
      assert_equal(["github"], Gem::CIDetector.ci_strings)
    end
    with_env("TASKCLUSTER_ROOT_URL" => "https://foo.bar", "DSARI" => "1", "CI_NAME" => "") do
      assert_equal(["dsari", "taskcluster"], Gem::CIDetector.ci_strings)
    end
  end

  private

  def with_env(overrides, &block)
    @orig_env = ENV.to_h
    ENV.replace(overrides)
    begin
      block.call
    ensure
      ENV.replace(@orig_env)
    end
  end
end
