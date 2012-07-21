require 'test/unit'

class TestHideSkip < Test::Unit::TestCase
  def test_hideskip
    test_out, o = IO.pipe
    spawn(*@options[:ruby], "#{File.dirname(__FILE__)}/test4test_redefinition.rb", out: File::NULL, err: o)
    o.close

    assert_match /^test\/unit warning: method TestForTestRedefinition#test_redefinition is redefined$/,
                 test_out.read
    test_out.close
  end
end
