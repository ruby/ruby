require 'rubygems/test_case'
require 'rubygems/util'

class TestGemUtil < Gem::TestCase

  def test_class_popen
    assert_equal "0\n", Gem::Util.popen(Gem.ruby, '-e', 'p 0')
  end

end

