require_relative '../helper'

module Psych
  module JSON
    class TestStream < TestCase
      def setup
        @io     = StringIO.new
        @stream = Psych::JSON::Stream.new(@io)
        @stream.start
      end

      def test_explicit_documents
        @io     = StringIO.new
        @stream = Psych::JSON::Stream.new(@io)
        @stream.start

        @stream.push({ 'foo' => 'bar' })

        assert !@stream.finished?, 'stream not finished'
        @stream.finish
        assert @stream.finished?, 'stream finished'

        assert_match(/^---/, @io.string)
        assert_match(/\.\.\.$/, @io.string)
      end

      def test_null
        @stream.push(nil)
        assert_match(/^--- null/, @io.string)
      end

      def test_string
        @stream.push "foo"
        assert_match(/(['"])foo\1/, @io.string)
      end

      def test_symbol
        @stream.push :foo
        assert_match(/(['"])foo\1/, @io.string)
      end

      def test_int
        @stream.push 10
        assert_match(/^--- 10/, @io.string)
      end

      def test_float
        @stream.push 1.2
        assert_match(/^--- 1.2/, @io.string)
      end

      def test_hash
        hash = { 'one' => 'two' }
        @stream.push hash

        json = @io.string
        assert_match(/}$/, json)
        assert_match(/^--- \{/, json)
        assert_match(/['"]one['"]/, json)
        assert_match(/['"]two['"]/, json)
      end

      def test_list_to_json
        list = %w{ one two }
        @stream.push list

        json = @io.string
        assert_match(/]$/, json)
        assert_match(/^--- \[/, json)
        assert_match(/['"]one['"]/, json)
        assert_match(/['"]two['"]/, json)
      end
    end
  end
end
