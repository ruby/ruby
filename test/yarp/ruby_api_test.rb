# frozen_string_literal: true

require "yarp_test_helper"

class YARPRubyAPITest < Test::Unit::TestCase
  def test_ruby_api
    filepath = __FILE__
    source = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)

    assert_equal YARP.lex(source, filepath).value, YARP.lex_file(filepath).value

    assert_equal YARP.dump(source, filepath), YARP.dump_file(filepath)

    serialized = YARP.dump(source, filepath)
    ast1 = YARP.load(source, serialized).value
    ast2 = YARP.parse(source, filepath).value
    ast3 = YARP.parse_file(filepath).value

    assert_equal_nodes ast1, ast2
    assert_equal_nodes ast2, ast3
  end
end
