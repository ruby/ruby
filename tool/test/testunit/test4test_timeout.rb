# frozen_string_literal: true
$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../../lib"

require 'test/unit'
require 'timeout'

class TestForTestTimeout < Test::Unit::TestCase
  10.times do |i|
    define_method("test_timeout_#{i}") do
      Timeout.timeout(0.001) do
        sleep
      end
    end
  end
end
