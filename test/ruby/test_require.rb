require 'test/unit'

require 'tempfile'
require_relative 'envutil'

class TestRequire < Test::Unit::TestCase
  def ruby(*r, &b)
    EnvUtil.rubyexec(*r, &b)
  end

  def test_require_invalid_shared_object
    t = Tempfile.new(["test_ruby_test_require", ".so"])
    t.puts "dummy"
    t.close

    ruby do |w, r, e|
      w.puts "begin"
      w.puts "  require \"#{ t.path }\""
      w.puts "rescue LoadError"
      w.puts "  p :ok"
      w.puts "end"
      w.close
      assert_equal(":ok", r.read.chomp)
    end
  end

  def test_require_too_long_filename
    ruby do |w, r, e|
      w.puts "begin"
      w.puts "  require '#{ "foo/" * 10000 }foo'"
      w.puts "rescue LoadError"
      w.puts "  p :ok"
      w.puts "end"
      w.close
      e.read
      assert_equal(":ok", r.read.chomp)
    end
  end

  def test_require_path_home
    env_rubypath, env_home = ENV["RUBYPATH"], ENV["HOME"]

    ENV["RUBYPATH"] = "~"
    ENV["HOME"] = "/foo" * 10000
    ruby("-S", "test_ruby_test_require") do |w, r, e|
      w.close
      e.read
      assert_equal("", r.read)
    end

    ENV["RUBYPATH"] = "~" + "/foo" * 10000
    ENV["HOME"] = "/foo"
    ruby("-S", "test_ruby_test_require") do |w, r, e|
      w.close
      e.read
      assert_equal("", r.read)
    end

    t = Tempfile.new(["test_ruby_test_require", ".rb"])
    t.puts "p :ok"
    t.close
    ENV["RUBYPATH"] = "~"
    ENV["HOME"], name = File.split(t.path)
    ruby("-S", name) do |w, r, e|
      w.close
      assert_equal(":ok", r.read.chomp)
      assert_equal("", e.read)
    end

  ensure
    env_rubypath ? ENV["RUBYPATH"] = env_rubypath : ENV.delete("RUBYPATH")
    env_home ? ENV["HOME"] = env_home : ENV.delete("HOME")
  end

  def test_define_class
    begin
      require "socket"
    rescue LoadError
      return
    end

    ruby do |w, r, e|
      w.puts "BasicSocket = 1"
      w.puts "begin"
      w.puts "  require 'socket'"
      w.puts "  p :ng"
      w.puts "rescue TypeError"
      w.puts "  p :ok"
      w.puts "end"
      w.close
      assert_equal("", e.read)
      assert_equal(":ok", r.read.chomp)
    end

    ruby do |w, r, e|
      w.puts "class BasicSocket; end"
      w.puts "begin"
      w.puts "  require 'socket'"
      w.puts "  p :ng"
      w.puts "rescue NameError"
      w.puts "  p :ok"
      w.puts "end"
      w.close
      assert_equal("", e.read)
      assert_equal(":ok", r.read.chomp)
    end

    ruby do |w, r, e|
      w.puts "class BasicSocket < IO; end"
      w.puts "begin"
      w.puts "  require 'socket'"
      w.puts "  p :ok"
      w.puts "rescue Exception"
      w.puts "  p :ng"
      w.puts "end"
      w.close
      assert_equal("", e.read)
      assert_equal(":ok", r.read.chomp)
    end
  end

  def test_define_class_under
    begin
      require "zlib"
    rescue LoadError
      return
    end

    ruby do |w, r, e|
      w.puts "module Zlib; end"
      w.puts "Zlib::Error = 1"
      w.puts "begin"
      w.puts "  require 'zlib'"
      w.puts "  p :ng"
      w.puts "rescue TypeError"
      w.puts "  p :ok"
      w.puts "end"
      w.close
      assert_equal("", e.read)
      assert_equal(":ok", r.read.chomp)
    end

    ruby do |w, r, e|
      w.puts "module Zlib; end"
      w.puts "class Zlib::Error; end"
      w.puts "begin"
      w.puts "  require 'zlib'"
      w.puts "  p :ng"
      w.puts "rescue NameError"
      w.puts "  p :ok"
      w.puts "end"
      w.close
      assert_equal("", e.read)
      assert_equal(":ok", r.read.chomp)
    end

    ruby do |w, r, e|
      w.puts "module Zlib; end"
      w.puts "class Zlib::Error < StandardError; end"
      w.puts "begin"
      w.puts "  require 'zlib'"
      w.puts "  p :ok"
      w.puts "rescue Exception"
      w.puts "  p :ng"
      w.puts "end"
      w.close
      assert_equal("", e.read)
      assert_equal(":ok", r.read.chomp)
    end
  end

  def test_define_module
    begin
      require "zlib"
    rescue LoadError
      return
    end

    ruby do |w, r, e|
      w.puts "Zlib = 1"
      w.puts "begin"
      w.puts "  require 'zlib'"
      w.puts "  p :ng"
      w.puts "rescue TypeError"
      w.puts "  p :ok"
      w.puts "end"
      w.close
      assert_equal("", e.read)
      assert_equal(":ok", r.read.chomp)
    end
  end

  def test_define_module_under
    begin
      require "socket"
    rescue LoadError
      return
    end

    ruby do |w, r, e|
      w.puts "class BasicSocket < IO; end"
      w.puts "class Socket < BasicSocket; end"
      w.puts "Socket::Constants = 1"
      w.puts "begin"
      w.puts "  require 'socket'"
      w.puts "  p :ng"
      w.puts "rescue TypeError"
      w.puts "  p :ok"
      w.puts "end"
      w.close
      assert_equal("", e.read)
      assert_equal(":ok", r.read.chomp)
    end
  end

  def test_load
    t = Tempfile.new(["test_ruby_test_require", ".rb"])
    t.puts "module Foo; end"
    t.puts "at_exit { p :wrap_end }"
    t.puts "at_exit { raise 'error in at_exit test' }"
    t.puts "p :ok"
    t.close

    ruby do |w, r, e|
      w.puts "load(#{ t.path.dump }, true)"
      w.puts "GC.start"
      w.puts "p :end"
      w.close
      assert_match(/error in at_exit test/, e.read)
      assert_equal(":ok\n:end\n:wrap_end", r.read.chomp)
    end

    assert_raise(ArgumentError) { at_exit }
  end
end
