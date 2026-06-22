# frozen_string_literal: true

require_relative 'test_helper'

begin
  require_relative './lib/helper'
rescue LoadError
end

class JSONInRactorTest < Test::Unit::TestCase
  unless Ractor.method_defined?(:value)
    module RactorBackport
      refine Ractor do
        alias_method :value, :take
      end
    end

    using RactorBackport
  end

  def test_generate
    pid = fork do
      Warning[:experimental] = false
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
      actual_json = r.value

      if expected_json == actual_json
        exit 0
      else
        puts "Expected:"
        puts expected_json
        puts "Actual:"
        puts actual_json
        puts
        exit 1
      end
    end
    _, status = Process.waitpid2(pid)
    assert_predicate status, :success?
  end

  def test_coder
    coder = JSON::Coder.new.freeze
    assert Ractor.shareable?(coder)
    pid = fork do
      Warning[:experimental] = false
      r = Ractor.new(coder) do |coder|
        json = coder.dump({
          'a' => 2,
          'b' => 3.141,
          'c' => 'c',
          'd' => [ 1, "b", 3.14 ],
          'e' => { 'foo' => 'bar' },
          'g' => "\"\0\037",
          'h' => 1000.0,
          'i' => 0.001
        })
        coder.load(json)
      end
      expected_json = JSON.parse('{"a":2,"b":3.141,"c":"c","d":[1,"b",3.14],"e":{"foo":"bar"},' +
                      '"g":"\\"\\u0000\\u001f","h":1000.0,"i":0.001}')
      actual_json = r.value

      if expected_json == actual_json
        exit 0
      else
        puts "Expected:"
        puts expected_json
        puts "Actual:"
        puts actual_json
        puts
        exit 1
      end
    end
    _, status = Process.waitpid2(pid)
    assert_predicate status, :success?
  end

  class NonNative
    def initialize(value)
      @value = value
    end
  end

  def test_coder_proc
    block = Ractor.shareable_proc { |value| value.as_json }
    coder = JSON::Coder.new(&block).freeze
    assert Ractor.shareable?(coder)

    pid = fork do
      Warning[:experimental] = false
      assert_equal [{}], Ractor.new(coder) { |coder|
        coder.load('[{}]')
      }.value
    end

    _, status = Process.waitpid2(pid)
    assert_predicate status, :success?
  end if Ractor.respond_to?(:shareable_proc)
end if defined?(Ractor) && Process.respond_to?(:fork)
