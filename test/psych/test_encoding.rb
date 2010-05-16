# -*- coding: utf-8 -*-

require_relative 'helper'

module Psych
  class TestEncoding < TestCase
    class EncodingCatcher < Handler
      attr_reader :strings
      def initialize
        @strings = []
      end

      (Handler.instance_methods(true) -
       Object.instance_methods).each do |m|
        class_eval %{
          def #{m} *args
            @strings += args.flatten.find_all { |a|
              String === a
            }
          end
        }
      end
    end

    def setup
      super
      @handler = EncodingCatcher.new
      @parser  = Psych::Parser.new @handler
      @utf8    = Encoding.find('UTF-8')
    end

    def test_default_internal
      before = Encoding.default_internal

      Encoding.default_internal = 'EUC-JP'

      str  = "壁に耳あり、障子に目あり"
      yaml = "--- #{str}"
      assert_equal @utf8, str.encoding

      @parser.parse str
      assert_encodings Encoding.find('EUC-JP'), @handler.strings
      assert_equal str, @handler.strings.first.encode('UTF-8')
    ensure
      Encoding.default_internal = before
    end

    def test_scalar
      @parser.parse("--- a")
      assert_encodings @utf8, @handler.strings
    end

    def test_alias
      @parser.parse(<<-eoyml)
%YAML 1.1
---
!!seq [
  !!str "Without properties",
  &A !!str "Anchored",
  !!str "Tagged",
  *A,
  !!str "",
]
      eoyml
      assert_encodings @utf8, @handler.strings
    end

    def test_list_anchor
      list = %w{ a b }
      list << list
      @parser.parse(Psych.dump(list))
      assert_encodings @utf8, @handler.strings
    end

    def test_map_anchor
      h = {}
      h['a'] = h
      @parser.parse(Psych.dump(h))
      assert_encodings @utf8, @handler.strings
    end

    def test_map_tag
      @parser.parse(<<-eoyml)
%YAML 1.1
---
!!map { a : b }
      eoyml
      assert_encodings @utf8, @handler.strings
    end

    def test_doc_tag
      @parser.parse(<<-eoyml)
%YAML 1.1
%TAG ! tag:tenderlovemaking.com,2009:
--- !fun
      eoyml
      assert_encodings @utf8, @handler.strings
    end

    private
    def assert_encodings encoding, strings
      strings.each do |str|
        assert_equal encoding, str.encoding, str
      end
    end
  end
end
