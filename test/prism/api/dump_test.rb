# frozen_string_literal: true

return if ENV["PRISM_BUILD_MINIMAL"]

require_relative "../test_helper"

module Ruby::Prism
  class DumpTest < TestCase
    Fixture.each do |fixture|
      define_method(fixture.test_name) { assert_dump(fixture) }
    end

    def test_dump
      filepath = __FILE__
      source = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)

      assert_equal Ruby::Prism.lex(source, filepath: filepath).value, Ruby::Prism.lex_file(filepath).value
      assert_equal Ruby::Prism.dump(source, filepath: filepath), Ruby::Prism.dump_file(filepath)

      serialized = Ruby::Prism.dump(source, filepath: filepath)
      ast1 = Ruby::Prism.load(source, serialized).value
      ast2 = Ruby::Prism.parse(source, filepath: filepath).value
      ast3 = Ruby::Prism.parse_file(filepath).value

      assert_equal_nodes ast1, ast2
      assert_equal_nodes ast2, ast3
    end

    def test_dump_file
      assert_nothing_raised do
        Ruby::Prism.dump_file(__FILE__)
      end

      error = assert_raise Errno::ENOENT do
        Ruby::Prism.dump_file("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Ruby::Prism.dump_file(nil)
      end
    end

    private

    def assert_dump(fixture)
      source = fixture.read

      result = Ruby::Prism.parse(source, filepath: fixture.path)
      dumped = Ruby::Prism.dump(source, filepath: fixture.path)

      assert_equal_nodes(result.value, Ruby::Prism.load(source, dumped).value)
    end
  end
end
