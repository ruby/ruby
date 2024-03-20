# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class MagicCommentTest < TestCase
    examples = [
      "# encoding: ascii",
      "# coding: ascii",
      "# eNcOdInG: ascii",
      "# CoDiNg: ascii",
      "# \s\t\v encoding \s\t\v : \s\t\v ascii \s\t\v",
      "# -*- encoding: ascii -*-",
      "# -*- coding: ascii -*-",
      "# -*- eNcOdInG: ascii -*-",
      "# -*- CoDiNg: ascii -*-",
      "# -*- \s\t\v encoding \s\t\v : \s\t\v ascii \s\t\v -*-",
      "# -*- foo: bar; encoding: ascii -*-",
      "# coding \t \r  \v   :     \t \v    \r   ascii-8bit",
      "# vim: filetype=ruby, fileencoding=windows-31j, tabsize=3, shiftwidth=3"
    ]

    examples.each.with_index(1) do |example, index|
      define_method(:"test_magic_comment_#{index}") do
        assert_magic_comment(example)
      end
    end

    private

    def assert_magic_comment(example)
      expected = Ripper.new(example).tap(&:parse).encoding
      actual = Prism.parse(example).encoding
      assert_equal expected, actual
    end
  end
end
