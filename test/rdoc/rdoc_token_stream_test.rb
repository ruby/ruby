# frozen_string_literal: true
require_relative 'helper'

class RDocTokenStreamTest < RDoc::TestCase

  def test_class_to_html
    tokens = [
      { :line_no => 0, :char_no => 0, :kind => :on_const, :text => 'CONSTANT' },
      { :line_no => 0, :char_no => 0, :kind => :on_kw, :text => 'KW' },
      { :line_no => 0, :char_no => 0, :kind => :on_ivar, :text => 'IVAR' },
      { :line_no => 0, :char_no => 0, :kind => :on_op, :text => 'Op' },
      { :line_no => 0, :char_no => 0, :kind => :on_ident, :text => 'Id' },
      { :line_no => 0, :char_no => 0, :kind => :on_backref, :text => 'Node' },
      { :line_no => 0, :char_no => 0, :kind => :on_comment, :text => 'COMMENT' },
      { :line_no => 0, :char_no => 0, :kind => :on_regexp, :text => 'REGEXP' },
      { :line_no => 0, :char_no => 0, :kind => :on_tstring, :text => 'STRING' },
      { :line_no => 0, :char_no => 0, :kind => :on_int, :text => 'Val' },
      { :line_no => 0, :char_no => 0, :kind => :on_unknown, :text => '\\' }
    ]

    expected = [
      '<span class="ruby-constant">CONSTANT</span>',
      '<span class="ruby-keyword">KW</span>',
      '<span class="ruby-ivar">IVAR</span>',
      '<span class="ruby-operator">Op</span>',
      '<span class="ruby-identifier">Id</span>',
      '<span class="ruby-node">Node</span>',
      '<span class="ruby-comment">COMMENT</span>',
      '<span class="ruby-regexp">REGEXP</span>',
      '<span class="ruby-string">STRING</span>',
      '<span class="ruby-value">Val</span>',
      '\\'
    ].join

    assert_equal expected, RDoc::TokenStream.to_html(tokens)
  end

  def test_class_to_html_empty
    assert_equal '', RDoc::TokenStream.to_html([])
  end

  def test_add_tokens
    foo = Class.new do
      include RDoc::TokenStream
    end.new
    foo.collect_tokens
    foo.add_tokens([:token])
    assert_equal [:token], foo.token_stream
  end

  def test_add_token
    foo = Class.new do
      include RDoc::TokenStream
    end.new
    foo.collect_tokens
    foo.add_token(:token)
    assert_equal [:token], foo.token_stream
  end

  def test_collect_tokens
    foo = Class.new do
      include RDoc::TokenStream
    end.new
    foo.collect_tokens
    assert_equal [], foo.token_stream
  end

  def test_pop_token
    foo = Class.new do
      include RDoc::TokenStream
    end.new
    foo.collect_tokens
    foo.add_token(:token)
    foo.pop_token
    assert_equal [], foo.token_stream
  end

  def test_token_stream
    foo = Class.new do
      include RDoc::TokenStream
    end.new
    assert_equal nil, foo.token_stream
  end

  def test_tokens_to_s
    foo = Class.new do
      include RDoc::TokenStream

      def initialize
        @token_stream = [
          { line_no: 0, char_no: 0, kind: :on_ident,   text: "foo" },
          { line_no: 0, char_no: 0, kind: :on_sp,      text: " " },
          { line_no: 0, char_no: 0, kind: :on_tstring, text: "'bar'" },
        ]
      end
    end.new

    assert_equal "foo 'bar'", foo.tokens_to_s

    foo = Class.new do
      include RDoc::TokenStream

      def initialize
        @token_stream = nil
      end
    end.new
    assert_equal "", foo.tokens_to_s
  end
end
