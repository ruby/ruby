# frozen_string_literal: false
require 'test/unit'

class TestRedefinition < Test::Unit::TestCase
  def test_redefinition
    assert_match(/^test\/unit warning: method TestForTestRedefinition#test_redefinition is redefined$/,
                 redefinition)
  end

  def redefinition(*args)
    IO.popen([*@options[:ruby], "#{File.dirname(__FILE__)}/test4test_redefinition.rb", *args],
                      err: [:child, :out]) {|f|
      f.read
    }
  end
end
