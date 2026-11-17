# frozen_string_literal: true

# Don't bother checking this on these engines, this is such a specific Ripper
# test.
return if RUBY_ENGINE != "ruby"

require_relative "test_helper"
require "ripper"

module Ruby::Prism
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

    def test_embedded_document
      source = "=begin\nignored\n=end\n1\n"
      assert_bom(source)
      result = Ruby::Prism.parse("\xEF\xBB\xBF#{source}")

      assert_predicate result, :success?
      assert_equal 1, result.statement.value
      assert_kind_of EmbDocComment, result.comments.first
      assert_equal 3, result.comments.first.location.start_offset
      assert_equal "=begin\nignored\n=end\n", result.comments.first.location.slice
    end

    def test_end_marker
      ["", "\n", "\r\n"].each do |newline|
        source = "__END__#{newline}"
        source += "data\n" unless newline.empty?
        assert_bom(source)
        result = Ruby::Prism.parse("\xEF\xBB\xBF#{source}")

        assert_predicate result, :success?
        assert_empty result.value.statements.body
        assert_not_nil result.data_loc
        assert_equal 3, result.data_loc.start_offset
        assert_equal source, result.data_loc.slice
      end
    end

    def test_indented_markers
      result = Ruby::Prism.parse("\xEF\xBB\xBF __END__\n")
      assert_predicate result, :success?
      assert_nil result.data_loc

      result = Ruby::Prism.parse("\xEF\xBB\xBF =begin\n=end\n")
      assert_predicate result, :failure?
      assert_empty result.comments
    end

    private

    def assert_bom(source)
      bommed = "\xEF\xBB\xBF#{source}"
      assert_equal Ripper.lex(bommed), Ruby::Prism.lex_compat(bommed).value
    end
  end
end
