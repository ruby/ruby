# frozen_string_literal: true

require_relative 'test_helper'

begin
  require_relative './lib/helper'
rescue LoadError
end

class JSONInRactorTest < Test::Unit::TestCase
  def test_generate
    pid = fork do
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
      expected_json = JSON.parse('{"a":2,"b":3.141,"c":"c","d":[1,"b",3.14],"e":{"foo":"bar"},' +
                      '"g":"\\"\\u0000\\u001f","h":1000.0,"i":0.001}')
      actual_json = r.take

      if expected_json == actual_json
        exit 0
      else
        puts "Expected:"
        puts expected_json
        puts "Acutual:"
        puts actual_json
        puts
        exit 1
      end
    end
    _, status = Process.waitpid2(pid)
    assert_predicate status, :success?
  end
end if defined?(Ractor) && Process.respond_to?(:fork)
