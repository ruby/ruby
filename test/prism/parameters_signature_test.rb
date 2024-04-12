# frozen_string_literal: true

require_relative "test_helper"

return if RUBY_VERSION < "3.2"

module Prism
  class ParametersSignatureTest < TestCase
    def test_req
      assert_parameters([[:req, :a]], "a")
    end

    def test_req_destructure
      assert_parameters([[:req]], "(a, b)")
    end

    def test_opt
      assert_parameters([[:opt, :a]], "a = 1")
    end

    def test_rest
      assert_parameters([[:rest, :a]], "*a")
    end

    def test_rest_anonymous
      assert_parameters([[:rest, :*]], "*")
    end

    def test_post
      assert_parameters([[:rest, :a], [:req, :b]], "*a, b")
    end

    def test_post_destructure
      assert_parameters([[:rest, :a], [:req]], "*a, (b, c)")
    end

    def test_keyreq
      assert_parameters([[:keyreq, :a]], "a:")
    end

    def test_key
      assert_parameters([[:key, :a]], "a: 1")
    end

    def test_keyrest
      assert_parameters([[:keyrest, :a]], "**a")
    end

    def test_nokey
      assert_parameters([[:nokey]], "**nil")
    end

    def test_keyrest_anonymous
      assert_parameters([[:keyrest, :**]], "**")
    end

    def test_key_ordering
      omit("TruffleRuby returns keys in order they were declared") if RUBY_ENGINE == "truffleruby"

      assert_parameters([[:keyreq, :a], [:keyreq, :b], [:key, :c], [:key, :d]], "a:, c: 1, b:, d: 2")
    end

    def test_block
      assert_parameters([[:block, :a]], "&a")
    end

    def test_block_anonymous
      assert_parameters([[:block, :&]], "&")
    end

    def test_forwarding
      assert_parameters([[:rest, :*], [:keyrest, :**], [:block, :&]], "...")
    end

    private

    def assert_parameters(expected, source)
      eval("def self.m(#{source}); end")

      begin
        assert_equal(expected, method(:m).parameters)
        assert_equal(expected, signature(source))
      ensure
        singleton_class.undef_method(:m)
      end
    end

    def signature(source)
      program = Prism.parse("def m(#{source}); end").value
      program.statements.body.first.parameters.signature
    end
  end
end
