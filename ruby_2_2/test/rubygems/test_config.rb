require 'rubygems/test_case'
require 'rubygems'

class TestConfig < Gem::TestCase

  def test_datadir
    util_make_gems
    spec = Gem::Specification.find_by_name("a")
    spec.activate
    assert_equal "#{spec.full_gem_path}/data/a", Gem.datadir('a')
  end

end

