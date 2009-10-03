require 'test/unit'
require 'rake'

# ====================================================================
class Rake::TestRequire < Test::Unit::TestCase
  RakeLibDir = File.dirname(__FILE__) + '/data/rakelib'

  def test_can_load_rake_library
    app = Rake::Application.new
    assert app.instance_eval {
      rake_require("test1", [RakeLibDir], [])
    }
  end

  def test_wont_reload_rake_library
    app = Rake::Application.new
    assert ! app.instance_eval {
      rake_require("test2", [RakeLibDir], ['test2'])
    }
  end

  def test_throws_error_if_library_not_found
    app = Rake::Application.new
    ex = assert_raise(LoadError) {
      assert app.instance_eval {
        rake_require("testx", [RakeLibDir], [])
      }
    }
    assert_match(/x/, ex.message)
  end
end

