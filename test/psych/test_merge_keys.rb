require_relative 'helper'

module Psych
  class TestMergeKeys < TestCase
    # [ruby-core:34679]
    def test_merge_key
      yaml = <<-eoyml
foo: &foo
  hello: world
bar:
  << : *foo
  baz: boo
      eoyml

      hash = {
        "foo" => { "hello" => "world"},
        "bar" => { "hello" => "world", "baz" => "boo" } }
      assert_equal hash, Psych.load(yaml)
    end
  end
end
