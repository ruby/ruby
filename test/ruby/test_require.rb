require 'test/unit'

require 'tempfile'
require File.expand_path('../envutil', __FILE__)
require 'tmpdir'

class TestRequire < Test::Unit::TestCase
  def test_home_path
    home = ENV["HOME"]
    bug3171 = '[ruby-core:29610]'
    Dir.mktmpdir do |tmp|
      ENV["HOME"] = tmp
      name = "loadtest#{$$}-1"
      path = File.join(tmp, name) << ".rb"
      open(path, "w") {}
      require "~/#{name}"
      assert_equal(path, $"[-1], bug3171)
      name.succ!
      path = File.join(tmp, name << ".rb")
      open(path, "w") {}
      require "~/#{name}"
      assert_equal(path, $"[-1], bug3171)
    end
  ensure
    ENV["HOME"] = home
  end
end
