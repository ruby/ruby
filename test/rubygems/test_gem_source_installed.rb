require 'rubygems/test_case'
require 'rubygems/source'

class TestGemSourceInstalled < Gem::TestCase

  def test_spaceship
    a1 = quick_gem 'a', '1'
    util_build_gem a1

    remote    = Gem::Source.new @gem_repo
    specific  = Gem::Source::SpecificFile.new a1.cache_file
    installed = Gem::Source::Installed.new
    local     = Gem::Source::Local.new

    assert_equal( 0, installed.<=>(installed), 'installed <=> installed')

    assert_equal(-1, remote.   <=>(installed), 'remote    <=> installed')
    assert_equal( 1, installed.<=>(remote),    'installed <=> remote')

    assert_equal( 1, installed.<=>(local),     'installed <=> local')
    assert_equal(-1, local.    <=>(installed), 'local     <=> installed')

    assert_equal(-1, specific. <=>(installed), 'specific  <=> installed')
    assert_equal( 1, installed.<=>(specific),  'installed <=> specific')
  end

end

