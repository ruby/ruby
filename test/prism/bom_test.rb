# frozen_string_literal: true

# Don't bother checking this on these engines, this is such a specific Ripper
# test.
return if RUBY_ENGINE == "jruby" || RUBY_ENGINE == "truffleruby"

require_relative "test_helper"

module Prism
  class BOMTest < TestCase
    def test_ident
      assert_bom("foo")
    end

    def test_back_reference
      assert_bom("$+")
    end

    def test_instance_variable
      assert_bom("@foo")
    end

    def test_class_variable
      assert_bom("@@foo")
    end

    def test_global_variable
      assert_bom("$foo")
    end

    def test_numbered_reference
      assert_bom("$1")
    end

    def test_percents
      assert_bom("%i[]")
      assert_bom("%r[]")
      assert_bom("%s[]")
      assert_bom("%q{}")
      assert_bom("%w[]")
      assert_bom("%x[]")
      assert_bom("%I[]")
      assert_bom("%W[]")
      assert_bom("%Q{}")
    end

    def test_string
      assert_bom("\"\"")
      assert_bom("''")
    end

    private

    def assert_bom(source)
      bommed = "\xEF\xBB\xBF#{source}"
      assert_equal Prism.lex_ripper(bommed), Prism.lex_compat(bommed).value
    end
  end
end
