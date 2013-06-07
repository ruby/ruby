require 'test/unit'
require_relative 'ruby/envutil'

# mathn redefines too much. It must be isolated to child processes.
class TestMathn < Test::Unit::TestCase
  def test_power
    assert_in_out_err ['-r', 'mathn', '-e', 'a=1**2;!a'], "", [], [], '[ruby-core:25740]'
    assert_in_out_err ['-r', 'mathn', '-e', 'a=(1<<126)**2;!a'], "", [], [], '[ruby-core:25740]'
    assert_in_out_err ['-r', 'mathn/complex', '-e', 'a=Complex(0,1)**4;!a'], "", [], [], '[ruby-core:44170]'
    assert_in_out_err ['-r', 'mathn/complex', '-e', 'a=Complex(0,1)**5;!a'], "", [], [], '[ruby-core:44170]'
  end

  def test_quo
    assert_in_out_err ['-r', 'mathn'], <<-EOS, %w(OK), [], '[ruby-core:41575]'
      1.quo(2); puts :OK
    EOS
  end
end
