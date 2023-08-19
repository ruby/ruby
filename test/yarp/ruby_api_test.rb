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

  def test_literal_value_method
    assert_equal 123, YARP.parse("123").value.statements.body.first.value
    assert_equal 3.14, YARP.parse("3.14").value.statements.body.first.value
    assert_equal 42i, YARP.parse("42i").value.statements.body.first.value
    assert_equal 3.14i, YARP.parse("3.14i").value.statements.body.first.value
    assert_equal 42r, YARP.parse("42r").value.statements.body.first.value
    assert_equal 0.5r, YARP.parse("0.5r").value.statements.body.first.value
    assert_equal 42ri, YARP.parse("42ri").value.statements.body.first.value
    assert_equal 0.5ri, YARP.parse("0.5ri").value.statements.body.first.value
  end
end
