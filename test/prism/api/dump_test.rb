# frozen_string_literal: true

return if ENV["PRISM_BUILD_MINIMAL"]

require_relative "../test_helper"

module Prism
  class DumpTest < TestCase
    Fixture.each do |fixture|
      define_method(fixture.test_name) { assert_dump(fixture) }
    end

    def test_dump
      filepath = __FILE__
      source = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)

      assert_equal Prism.lex(source, filepath: filepath).value, Prism.lex_file(filepath).value
      assert_equal Prism.dump(source, filepath: filepath), Prism.dump_file(filepath)

      serialized = Prism.dump(source, filepath: filepath)
      ast1 = Prism.load(source, serialized).value
      ast2 = Prism.parse(source, filepath: filepath).value
      ast3 = Prism.parse_file(filepath).value

      assert_equal_nodes ast1, ast2
      assert_equal_nodes ast2, ast3
    end

    def test_dump_file
      assert_nothing_raised do
        Prism.dump_file(__FILE__)
      end

      error = assert_raise Errno::ENOENT do
        Prism.dump_file("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Prism.dump_file(nil)
      end
    end

    private

    def assert_dump(fixture)
      source = fixture.read

      result = Prism.parse(source, filepath: fixture.path)
      dumped = Prism.dump(source, filepath: fixture.path)

      assert_equal_nodes(result.value, Prism.load(source, dumped).value)
    end
  end
end
