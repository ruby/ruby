require_relative '../ruby/envutil'
require 'test/unit'

class TestGemActivation < Test::Unit::TestCase
  def test_activation
    bug3140 = '[ruby-core:29486]'
    src = %{begin
  require 'rubygems-bug-parent'
rescue Gem::LoadError
  puts $!
else
  puts $bug_3140
end}
    basedir = File.expand_path("../gems/current", __FILE__)
    env = {"HOME"=>basedir, "GEM_HOME"=>basedir, "GEM_PATH"=>basedir}
    # WONTFIX in 1.9.2
    #assert_in_out_err([env, "-rrubygems-bug-child", "-e", src], "",
    #                  /can't activate rubygems-bug-child.*already activated rubygems-bug-child-1\.1/, [],
    #                  bug3140)
  end
end if defined?(::Gem) and RUBY_VERSION < "1.9"
