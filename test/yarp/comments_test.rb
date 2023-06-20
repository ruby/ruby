# frozen_string_literal: true

require "yarp_test_helper"

class CommentsTest < Test::Unit::TestCase
  include ::YARP::DSL

  def test_comment_inline
    assert_comment "# comment", :inline
  end

  def test_comment___END__
    source = <<~RUBY
      __END__
      comment
    RUBY

    assert_comment source, :__END__
  end

  def test_comment_embedded_document
    source = <<~RUBY
      =begin
      comment
      =end
    RUBY

    assert_comment source, :embdoc
  end

  def test_comment_embedded_document_with_content_on_same_line
    source = <<~RUBY
      =begin other stuff
      =end
    RUBY

    assert_comment source, :embdoc
  end

  private

  def assert_comment(source, type)
    result = YARP.parse(source)
    assert result.errors.empty?, result.errors.map(&:message).join("\n")
    result => YARP::ParseResult[comments: [YARP::Comment[type: type]]]
  end
end
