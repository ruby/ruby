# frozen_string_literal: true

require "test_helper"

class CommentsTest < Test::Unit::TestCase
  include YARP::DSL

  test "comment inline" do
    assert_comment "# comment", :inline
  end

  test "comment __END__" do
    source = <<~RUBY
      __END__
      comment
    RUBY

    assert_comment source, :__END__
  end

  test "comment embedded document" do
    source = <<~RUBY
      =begin
      comment
      =end
    RUBY

    assert_comment source, :embdoc
  end

  test "comment embedded document with content on same line" do
    source = <<~RUBY
      =begin other stuff
      =end
    RUBY

    assert_comment source, :embdoc
  end

  private

  def assert_comment(source, type)
    result = YARP.parse_dup(source)
    assert result.errors.empty?, result.errors.map(&:message).join("\n")
    result => YARP::ParseResult[comments: [YARP::Comment[type: type]]]
  end
end
