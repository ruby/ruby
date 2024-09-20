# frozen_string_literal: false

require_relative 'test_helper'

begin
  require_relative './lib/helper'
rescue LoadError
end

class JSONInRactorTest < Test::Unit::TestCase
  def test_generate
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      $VERBOSE = nil
      require "json"
      r = Ractor.new do
        json = JSON.generate({
          'a' => 2,
          'b' => 3.141,
          'c' => 'c',
          'd' => [ 1, "b", 3.14 ],
          'e' => { 'foo' => 'bar' },
          'g' => "\"\0\037",
          'h' => 1000.0,
          'i' => 0.001
        })
        JSON.parse(json)
      end
      expected_json = '{"a":2,"b":3.141,"c":"c","d":[1,"b",3.14],"e":{"foo":"bar"},' +
                      '"g":"\\"\\u0000\\u001f","h":1000.0,"i":0.001}'
      assert_equal(JSON.parse(expected_json), r.take)
    end;
  end
end if defined?(Ractor)
