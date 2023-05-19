# frozen_string_literal: true

require "test_helper"

class CommentsTest < Test::Unit::TestCase
  include YARP::DSL

  def test_comment_inline
    assert_comment "# comment", :inline
  end

  def test_comment__END__
    source = <<~RUBY
      __END__
      comment
    RUBY

    assert_comment source, :__END__
  end

  private

  def assert_comment(source, type)
    result = YARP.parse_dup(source)
    assert result.errors.empty?, result.errors.map(&:message).join("\n")
    result => YARP::ParseResult[comments: [YARP::Comment[type: type]]]
  end
end
