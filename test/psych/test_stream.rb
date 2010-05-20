require_relative 'helper'

module Psych
  class TestStream < TestCase
    def test_explicit_documents
      io     = StringIO.new
      stream = Psych::Stream.new(io)
      stream.start
      stream.push({ 'foo' => 'bar' })

      assert !stream.finished?, 'stream not finished'
      stream.finish
      assert stream.finished?, 'stream finished'

      assert_match(/^---/, io.string)
      assert_match(/\.\.\.$/, io.string)
    end

    def test_start_takes_block
      io     = StringIO.new
      stream = Psych::Stream.new(io)
      stream.start do |emitter|
        emitter.push({ 'foo' => 'bar' })
      end

      assert stream.finished?, 'stream finished'
      assert_match(/^---/, io.string)
      assert_match(/\.\.\.$/, io.string)
    end

    def test_no_backreferences
      io     = StringIO.new
      stream = Psych::Stream.new(io)
      stream.start do |emitter|
        x = { 'foo' => 'bar' }
        emitter.push x
        emitter.push x
      end

      assert stream.finished?, 'stream finished'
      assert_match(/^---/, io.string)
      assert_match(/\.\.\.$/, io.string)
      assert_equal 2, io.string.scan('---').length
      assert_equal 2, io.string.scan('...').length
      assert_equal 2, io.string.scan('foo').length
      assert_equal 2, io.string.scan('bar').length
    end
  end
end
