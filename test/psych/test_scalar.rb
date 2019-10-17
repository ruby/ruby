# -*- coding: utf-8 -*-
# frozen_string_literal: true

require_relative 'helper'

module Psych
  class TestScalar < TestCase
    def test_utf_8
      assert_equal "日本語", Psych.load("--- 日本語")
    end

    def test_some_bytes # Ticket #278
      x = "\xEF\xBF\xBD\x1F"
      assert_cycle x
    end
  end
end
