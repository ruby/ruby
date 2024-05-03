# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class IndexWriteTest < TestCase
    def test_keywords_3_3
      assert_parse_success(<<~RUBY, "3.3.0")
        foo[bar: 1] = 1
        foo[bar: 1] &&= 1
        foo[bar: 1] ||= 1
        foo[bar: 1] += 1
      RUBY

      assert_parse_success(<<~RUBY, "3.3.0")
        def foo(**)
          bar[**] = 1
          bar[**] &&= 1
          bar[**] ||= 1
          bar[**] += 1
        end
      RUBY
    end

    def test_block_3_3
      assert_parse_success(<<~RUBY, "3.3.0")
        foo[&bar] = 1
        foo[&bar] &&= 1
        foo[&bar] ||= 1
        foo[&bar] += 1
      RUBY

      assert_parse_success(<<~RUBY, "3.3.0")
        def foo(&)
          bar[&] = 1
          bar[&] &&= 1
          bar[&] ||= 1
          bar[&] += 1
        end
      RUBY
    end

    def test_keywords_latest
      assert_parse_failure(<<~RUBY)
        foo[bar: 1] = 1
        foo[bar: 1] &&= 1
        foo[bar: 1] ||= 1
        foo[bar: 1] += 1
      RUBY

      assert_parse_failure(<<~RUBY)
        def foo(**)
          bar[**] = 1
          bar[**] &&= 1
          bar[**] ||= 1
          bar[**] += 1
        end
      RUBY
    end

    def test_block_latest
      assert_parse_failure(<<~RUBY)
        foo[&bar] = 1
        foo[&bar] &&= 1
        foo[&bar] ||= 1
        foo[&bar] += 1
      RUBY

      assert_parse_failure(<<~RUBY)
        def foo(&)
          bar[&] = 1
          bar[&] &&= 1
          bar[&] ||= 1
          bar[&] += 1
        end
      RUBY
    end

    private

    def assert_parse_success(source, version = "latest")
      assert Prism.parse_success?(source, version: version)
    end

    def assert_parse_failure(source, version = "latest")
      assert Prism.parse_failure?(source, version: version)
    end
  end
end
