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
      @buffer  = StringIO.new
      @handler = EncodingCatcher.new
      @parser  = Psych::Parser.new @handler
      @utf8    = Encoding.find('UTF-8')
      @emitter = Psych::Emitter.new @buffer
    end

    def test_emit_alias
      @emitter.start_stream Psych::Parser::UTF8
      @emitter.start_document [], [], true
      e = assert_raises(RuntimeError) do
        @emitter.alias 'ドラえもん'.encode('EUC-JP')
      end
      assert_match(/alias value/, e.message)
    end

    def test_start_mapping
      foo = 'foo'
      bar = 'バー'

      @emitter.start_stream Psych::Parser::UTF8
      @emitter.start_document [], [], true
      @emitter.start_mapping(
        foo.encode('Shift_JIS'),
        bar.encode('UTF-16LE'),
        false, Nodes::Sequence::ANY)
      @emitter.end_mapping
      @emitter.end_document false
      @emitter.end_stream

      @parser.parse @buffer.string
      assert_encodings @utf8, @handler.strings
      assert_equal [foo, bar], @handler.strings
    end

    def test_start_sequence
      foo = 'foo'
      bar = 'バー'

      @emitter.start_stream Psych::Parser::UTF8
      @emitter.start_document [], [], true
      @emitter.start_sequence(
        foo.encode('Shift_JIS'),
        bar.encode('UTF-16LE'),
        false, Nodes::Sequence::ANY)
      @emitter.end_sequence
      @emitter.end_document false
      @emitter.end_stream

      @parser.parse @buffer.string
      assert_encodings @utf8, @handler.strings
      assert_equal [foo, bar], @handler.strings
    end

    def test_doc_tag_encoding
      key = '鍵'
      @emitter.start_stream Psych::Parser::UTF8
      @emitter.start_document(
        [1, 1],
        [['!'.encode('EUC-JP'), key.encode('EUC-JP')]],
        true
      )
      @emitter.scalar 'foo', nil, nil, true, false, Nodes::Scalar::ANY
      @emitter.end_document false
      @emitter.end_stream

      @parser.parse @buffer.string
      assert_encodings @utf8, @handler.strings
      assert_equal key, @handler.strings[1]
    end

    def test_emitter_encoding
      str  = "壁に耳あり、障子に目あり"
      thing = Psych.load Psych.dump str.encode('EUC-JP')
      assert_equal str, thing
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
