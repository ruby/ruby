require 'test/unit'

require 'tempfile'
require_relative 'envutil'
require 'tmpdir'

class TestRequire < Test::Unit::TestCase
  def test_require_invalid_shared_object
    t = Tempfile.new(["test_ruby_test_require", ".so"])
    t.puts "dummy"
    t.close

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      begin
        require \"#{ t.path }\"
      rescue LoadError
        p :ok
      end
    INPUT
  end

  def test_require_too_long_filename
    assert_in_out_err(["RUBYOPT"=>nil], <<-INPUT, %w(:ok), [])
      begin
        require '#{ "foo/" * 10000 }foo'
      rescue LoadError
        p :ok
      end
    INPUT

    begin
      assert_in_out_err(["-S", "-w", "foo/" * 1024 + "foo"], "") do |r, e|
        assert_equal([], r)
        assert_operator(2, :<=, e.size)
        assert_match(/warning: openpath: pathname too long \(ignored\)/, e.first)
        assert_match(/\(LoadError\)/, e.last)
      end
    rescue Errno::EINVAL
      # too long commandline may be blocked by OS.
    end
  end

  def test_require_nonascii
    bug3758 = '[ruby-core:31915]'
    e = assert_raise(LoadError, bug3758) {require "\u{221e}"}
    assert_match(/\u{221e}\z/, e.message, bug3758)
  end

  def test_require_path_home_1
    env_rubypath, env_home = ENV["RUBYPATH"], ENV["HOME"]
    pathname_too_long = /pathname too long \(ignored\).*\(LoadError\)/m

    ENV["RUBYPATH"] = "~"
    ENV["HOME"] = "/foo" * 1024
    assert_in_out_err(%w(-S -w test_ruby_test_require), "", [], pathname_too_long)

  ensure
    env_rubypath ? ENV["RUBYPATH"] = env_rubypath : ENV.delete("RUBYPATH")
    env_home ? ENV["HOME"] = env_home : ENV.delete("HOME")
  end

  def test_require_path_home_2
    env_rubypath, env_home = ENV["RUBYPATH"], ENV["HOME"]
    pathname_too_long = /pathname too long \(ignored\).*\(LoadError\)/m

    ENV["RUBYPATH"] = "~" + "/foo" * 1024
    ENV["HOME"] = "/foo"
    assert_in_out_err(%w(-S -w test_ruby_test_require), "", [], pathname_too_long)

  ensure
    env_rubypath ? ENV["RUBYPATH"] = env_rubypath : ENV.delete("RUBYPATH")
    env_home ? ENV["HOME"] = env_home : ENV.delete("HOME")
  end

  def test_require_path_home_3
    env_rubypath, env_home = ENV["RUBYPATH"], ENV["HOME"]

    t = Tempfile.new(["test_ruby_test_require", ".rb"])
    t.puts "p :ok"
    t.close

    ENV["RUBYPATH"] = "~"
    ENV["HOME"] = t.path
    assert_in_out_err(%w(-S test_ruby_test_require), "", [], /\(LoadError\)/)

    ENV["HOME"], name = File.split(t.path)
    assert_in_out_err(["-S", name], "", %w(:ok), [])

  ensure
    env_rubypath ? ENV["RUBYPATH"] = env_rubypath : ENV.delete("RUBYPATH")
    env_home ? ENV["HOME"] = env_home : ENV.delete("HOME")
  end

  def test_require_with_unc
    assert(system(File.expand_path(EnvUtil.rubybin).sub(/\A(\w):/, '//127.0.0.1/\1$/'), "-rabbrev", "-e0"))
  end if /mswin|mingw/ =~ RUBY_PLATFORM

  def test_define_class
    begin
      require "socket"
    rescue LoadError
      return
    end

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      BasicSocket = 1
      begin
        require 'socket'
        p :ng
      rescue TypeError
        p :ok
      end
    INPUT

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      class BasicSocket; end
      begin
        require 'socket'
        p :ng
      rescue TypeError
        p :ok
      end
    INPUT

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      class BasicSocket < IO; end
      begin
        require 'socket'
        p :ok
      rescue Exception
        p :ng
      end
    INPUT
  end

  def test_define_class_under
    begin
      require "zlib"
    rescue LoadError
      return
    end

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      module Zlib; end
      Zlib::Error = 1
      begin
        require 'zlib'
        p :ng
      rescue TypeError
        p :ok
      end
    INPUT

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      module Zlib; end
      class Zlib::Error; end
      begin
        require 'zlib'
        p :ng
      rescue NameError
        p :ok
      end
    INPUT

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      module Zlib; end
      class Zlib::Error < StandardError; end
      begin
        require 'zlib'
        p :ok
      rescue Exception
        p :ng
      end
    INPUT
  end

  def test_define_module
    begin
      require "zlib"
    rescue LoadError
      return
    end

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      Zlib = 1
      begin
        require 'zlib'
        p :ng
      rescue TypeError
        p :ok
      end
    INPUT
  end

  def test_define_module_under
    begin
      require "socket"
    rescue LoadError
      return
    end

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      class BasicSocket < IO; end
      class Socket < BasicSocket; end
      Socket::Constants = 1
      begin
        require 'socket'
        p :ng
      rescue TypeError
        p :ok
      end
    INPUT
  end

  def test_load
    t = Tempfile.new(["test_ruby_test_require", ".rb"])
    t.puts "module Foo; end"
    t.puts "at_exit { p :wrap_end }"
    t.puts "at_exit { raise 'error in at_exit test' }"
    t.puts "p :ok"
    t.close

    assert_in_out_err([], <<-INPUT, %w(:ok :end :wrap_end), /error in at_exit test/)
      load(#{ t.path.dump }, true)
      GC.start
      p :end
    INPUT

    assert_raise(ArgumentError) { at_exit }
  end

  def test_load2  # [ruby-core:25039]
    t = Tempfile.new(["test_ruby_test_require", ".rb"])
    t.puts "Hello = 'hello'"
    t.puts "class Foo"
    t.puts "  p Hello"
    t.puts "end"
    t.close

    assert_in_out_err([], <<-INPUT, %w("hello"), [])
      load(#{ t.path.dump }, true)
    INPUT
  end

  def test_tainted_loadpath
    t = Tempfile.new(["test_ruby_test_require", ".rb"])
    abs_dir, file = File.split(t.path)
    abs_dir = File.expand_path(abs_dir).untaint

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      abs_dir = "#{ abs_dir }"
      $: << abs_dir
      require "#{ file }"
      p :ok
    INPUT

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      abs_dir = "#{ abs_dir }"
      $: << abs_dir.taint
      require "#{ file }"
      p :ok
    INPUT

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      abs_dir = "#{ abs_dir }"
      $: << abs_dir.taint
      $SAFE = 1
      begin
        require "#{ file }"
      rescue SecurityError
        p :ok
      end
    INPUT

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      abs_dir = "#{ abs_dir }"
      $: << abs_dir.taint
      $SAFE = 1
      begin
        require "#{ file }"
      rescue SecurityError
        p :ok
      end
    INPUT

    assert_in_out_err([], <<-INPUT, %w(:ok), [])
      abs_dir = "#{ abs_dir }"
      $: << abs_dir << 'elsewhere'.taint
      require "#{ file }"
      p :ok
    INPUT
  end

  def test_relative
    load_path = $:.dup
    $:.delete(".")
    Dir.mktmpdir do |tmp|
      Dir.chdir(tmp) do
        Dir.mkdir('x')
        File.open('x/t.rb', 'wb') {}
        File.open('x/a.rb', 'wb') {|f| f.puts("require_relative('t.rb')")}
        assert require('./x/t.rb')
        assert !require(File.expand_path('x/t.rb'))
        assert_nothing_raised(LoadError) {require('./x/a.rb')}
        assert_raise(LoadError) {require('x/t.rb')}
        File.unlink(*Dir.glob('x/*'))
        Dir.rmdir("#{tmp}/x")
        $:.replace(load_path)
        load_path = nil
        assert(!require('tmpdir'))
      end
    end
  ensure
    $:.replace(load_path) if load_path
  end

  def test_relative_symlink
    Dir.mktmpdir {|tmp|
      Dir.chdir(tmp) {
        Dir.mkdir "a"
        Dir.mkdir "b"
        File.open("a/lib.rb", "w") {|f| f.puts 'puts "a/lib.rb"' }
        File.open("b/lib.rb", "w") {|f| f.puts 'puts "b/lib.rb"' }
        File.open("a/tst.rb", "w") {|f| f.puts 'require_relative "lib"' }
        begin
          File.symlink("../a/tst.rb", "b/tst.rb")
          result = IO.popen([EnvUtil.rubybin, "b/tst.rb"]).read
          assert_equal("a/lib.rb\n", result, "[ruby-dev:40040]")
        rescue NotImplementedError
          skip "File.symlink is not implemented"
        end
      }
    }
  end

  def test_frozen_loaded_features
    bug3756 = '[ruby-core:31913]'
    assert_in_out_err(['-e', '$LOADED_FEATURES.freeze; require "ostruct"'], "",
                      [], /\$LOADED_FEATURES is frozen; cannot append feature \(RuntimeError\)$/,
                      bug3756)
  end

  def test_case_insensitive
    load_path = $:.dup
    loaded = $".dup
    path = File.expand_path(__FILE__)
    $:.unshift(File.dirname(path))
    $".push(path) unless $".include?(path)
    bug4255 = '[ruby-core:34297]'
    assert_equal(false, $bug4255 ||= false, bug4255)
    $bug4255 = true
    f = File.basename(__FILE__, ".*").upcase
    assert_equal(false, require(f))
  ensure
    $:.replace(load_path)
    $".replace(loaded)
  end if File.identical?(__FILE__, __FILE__.upcase)

  def test_feature_is_reloaded_from_new_load_path_entry
    # This is a bit of a weird test, but it is needed to ensure that some
    # caching optimizations are working correctly.
    load_path      = $:.dup
    loaded         = $".dup
    initial_length = loaded.length

    Dir.mktmpdir do |tmp|
      Dir.chdir(tmp) do
        Dir.mkdir "a"
        Dir.mkdir "b"
        File.open("a/test.rb", "w") {|f| f.puts '' }
        File.open("b/test.rb", "w") {|f| f.puts '' }

        $".clear
        $:.unshift(File.join(tmp, "b"))
        require 'test.rb'
        assert $"[0].include?('b/test.rb')

        $".clear
        $:.unshift(File.join(tmp, "a"))
        require 'test.rb'
        assert $"[0].include?('a/test.rb')
      end
    end
  ensure
    $:.replace(load_path)
    $".replace(loaded)
  end

  def test_require_file_with_multiple_dots
    load_path      = $:.dup
    loaded         = $".dup
    initial_length = loaded.length

    Dir.mktmpdir do |tmp|
      Dir.chdir(tmp) do
        Dir.mkdir "a"
        File.open("a/test.1.rb", "w") {|f| f.puts '' }

        $".clear
        $:.unshift(File.join(tmp, "a"))
        require 'test.1'
        assert $"[0].include?('test.1.rb')

        $".clear
        File.open("a/test.rb.rb", "w") {|f| f.puts '' }
        File.open("a/test.rb", "w") {|f| f.puts '' }

        require 'test.rb'
        assert !$"[0].include?('test.rb.rb')
      end
    end
  ensure
    $:.replace(load_path)
    $".replace(loaded)
  end
end
