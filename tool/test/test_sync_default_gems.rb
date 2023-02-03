#!/usr/bin/ruby
require 'test/unit'
require 'stringio'
require_relative '../sync_default_gems'

module Test_SyncDefaultGems
  class TestMessageFilter < Test::Unit::TestCase
    def assert_message_filter(expected, trailers, input, repo = "ruby/test", sha = "0123456789")
      subject, *expected = expected
      expected = [
        "[#{repo}] #{subject}\n",
        *expected.map {_1+"\n"},
        "\n",
        "https://github.com/#{repo}/commit/#{sha[0, 10]}\n",
      ]
      if trailers
        expected << "\n"
        expected.concat(trailers.map {_1+"\n"})
      end

      out, err = capture_output do
        SyncDefaultGems.message_filter(repo, sha, input: StringIO.new(input, "r"))
      end

      all_assertions do |a|
        a.for("error") {assert_empty err}
        a.for("result") {assert_pattern_list(expected, out)}
      end
    end

    def test_subject_only
      expected = [
        "initial commit",
      ]
      assert_message_filter(expected, nil, "initial commit")
    end

    def test_link_in_parenthesis
      expected = [
        "fix (https://github.com/ruby/test/pull/1)",
      ]
      assert_message_filter(expected, nil, "fix (#1)")
    end

    def test_co_authored_by
      expected = [
        "commit something",
      ]
      trailers = [
        "Co-Authored-By: git <git@ruby-lang.org>",
      ]
      assert_message_filter(expected, trailers, [expected, "", trailers, ""].join("\n"))
    end

    def test_multiple_co_authored_by
      expected = [
        "many commits",
      ]
      trailers = [
        "Co-authored-by: git <git@ruby-lang.org>",
        "Co-authored-by: svn <svn@ruby-lang.org>",
      ]
      assert_message_filter(expected, trailers, [expected, "", trailers, ""].join("\n"))
    end

    def test_co_authored_by_no_newline
      expected = [
        "commit something",
      ]
      trailers = [
        "Co-Authored-By: git <git@ruby-lang.org>",
      ]
      assert_message_filter(expected, trailers, [expected, "", trailers].join("\n"))
    end
  end
end
