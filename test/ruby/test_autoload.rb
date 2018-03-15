# frozen_string_literal: false
require 'test/unit'
require 'tempfile'

class TestAutoload < Test::Unit::TestCase
  def test_autoload_so
    # Date is always available, unless excluded intentionally.
    assert_in_out_err([], <<-INPUT, [], [])
    autoload :Date, "date"
    begin Date; rescue LoadError; end
    INPUT
  end

  def test_non_realpath_in_loadpath
    require 'tmpdir'
    tmpdir = Dir.mktmpdir('autoload')
    tmpdirs = [tmpdir]
    tmpdirs.unshift(tmpdir + '/foo')
    Dir.mkdir(tmpdirs[0])
    tmpfiles = [tmpdir + '/foo.rb', tmpdir + '/foo/bar.rb']
    open(tmpfiles[0] , 'w') do |f|
      f.puts <<-INPUT
$:.unshift(File.expand_path('..', __FILE__)+'/./foo')
module Foo
  autoload :Bar, 'bar'
end
p Foo::Bar
      INPUT
    end
    open(tmpfiles[1], 'w') do |f|
      f.puts 'class Foo::Bar; end'
    end
    assert_in_out_err([tmpfiles[0]], "", ["Foo::Bar"], [])
  ensure
    File.unlink(*tmpfiles) rescue nil if tmpfiles
    tmpdirs.each {|dir| Dir.rmdir(dir)}
  end

  def test_autoload_p
    bug4565 = '[ruby-core:35679]'

    require 'tmpdir'
    Dir.mktmpdir('autoload') {|tmpdir|
      tmpfile = tmpdir + '/foo.rb'
      a = Module.new do
        autoload :X, tmpfile
      end
      b = Module.new do
        include a
      end
      assert_equal(true, a.const_defined?(:X))
      assert_equal(true, b.const_defined?(:X))
      assert_equal(tmpfile, a.autoload?(:X), bug4565)
      assert_equal(tmpfile, b.autoload?(:X), bug4565)
    }
  end

  def test_autoload_with_unqualified_file_name # [ruby-core:69206]
    lp = $LOAD_PATH.dup
    lf = $LOADED_FEATURES.dup

    Dir.mktmpdir('autoload') { |tmpdir|
      $LOAD_PATH << tmpdir

      Dir.chdir(tmpdir) do
        eval <<-END
          class ::Object
            module A
              autoload :C, 'b'
            end
          end
        END

        File.open('b.rb', 'w') {|file| file.puts 'module A; class C; end; end'}
        assert_kind_of Class, ::A::C
      end
    }
  ensure
    $LOAD_PATH.replace lp
    $LOADED_FEATURES.replace lf
    Object.send(:remove_const, :A) if Object.const_defined?(:A)
  end

  def test_require_explicit
    Tempfile.create(['autoload', '.rb']) {|file|
      file.puts 'class Object; AutoloadTest = 1; end'
      file.close
      add_autoload(file.path)
      begin
        assert_nothing_raised do
          assert(require file.path)
          assert_equal(1, ::AutoloadTest)
        end
      ensure
        remove_autoload_constant
      end
    }
  end

  def test_threaded_accessing_constant
    # Suppress "warning: loading in progress, circular require considered harmful"
    EnvUtil.default_warning {
      Tempfile.create(['autoload', '.rb']) {|file|
        file.puts 'sleep 0.5; class AutoloadTest; X = 1; end'
        file.close
        add_autoload(file.path)
        begin
          assert_nothing_raised do
            t1 = Thread.new { ::AutoloadTest::X }
            t2 = Thread.new { ::AutoloadTest::X }
            [t1, t2].each(&:join)
          end
        ensure
          remove_autoload_constant
        end
      }
    }
  end

  def test_threaded_accessing_inner_constant
    # Suppress "warning: loading in progress, circular require considered harmful"
    EnvUtil.default_warning {
      Tempfile.create(['autoload', '.rb']) {|file|
        file.puts 'class AutoloadTest; sleep 0.5; X = 1; end'
        file.close
        add_autoload(file.path)
        begin
          assert_nothing_raised do
            t1 = Thread.new { ::AutoloadTest::X }
            t2 = Thread.new { ::AutoloadTest::X }
            [t1, t2].each(&:join)
          end
        ensure
          remove_autoload_constant
        end
      }
    }
  end

  def test_nameerror_when_autoload_did_not_define_the_constant
    Tempfile.create(['autoload', '.rb']) {|file|
      file.puts ''
      file.close
      add_autoload(file.path)
      begin
        assert_raise(NameError) do
          AutoloadTest
        end
      ensure
        remove_autoload_constant
      end
    }
  end

  def test_override_autoload
    Tempfile.create(['autoload', '.rb']) {|file|
      file.puts ''
      file.close
      add_autoload(file.path)
      begin
        eval %q(class AutoloadTest; end)
        assert_equal(Class, AutoloadTest.class)
      ensure
        remove_autoload_constant
      end
    }
  end

  def test_override_while_autoloading
    Tempfile.create(['autoload', '.rb']) {|file|
      file.puts 'class AutoloadTest; sleep 0.5; end'
      file.close
      add_autoload(file.path)
      begin
        # while autoloading...
        t = Thread.new { AutoloadTest }
        sleep 0.1
        # override it
        EnvUtil.suppress_warning {
          eval %q(AutoloadTest = 1)
        }
        t.join
        assert_equal(1, AutoloadTest)
      ensure
        remove_autoload_constant
      end
    }
  end

  def ruby_impl_require
    Kernel.module_eval do
      alias old_require require
    end
    called_with = []
    Kernel.send :define_method, :require do |path|
      called_with << path
      old_require path
    end
    yield called_with
  ensure
    Kernel.module_eval do
      undef require
      alias require old_require
      undef old_require
    end
  end

  def test_require_implemented_in_ruby_is_called
    ruby_impl_require do |called_with|
      Tempfile.create(['autoload', '.rb']) {|file|
        file.puts 'class AutoloadTest; end'
        file.close
        add_autoload(file.path)
        begin
          assert(Object::AutoloadTest)
        ensure
          remove_autoload_constant
        end
        assert_equal [file.path], called_with
      }
    end
  end

  def test_autoload_while_autoloading
    ruby_impl_require do |called_with|
      Tempfile.create(%w(a .rb)) do |a|
        Tempfile.create(%w(b .rb)) do |b|
          a.puts "require '#{b.path}'; class AutoloadTest; end"
          b.puts "class AutoloadTest; module B; end; end"
          [a, b].each(&:flush)
          add_autoload(a.path)
          begin
            assert(Object::AutoloadTest)
          ensure
            remove_autoload_constant
          end
          assert_equal [a.path, b.path], called_with
        end
      end
    end
  end

  def test_bug_13526
    script = File.join(__dir__, 'bug-13526.rb')
    assert_ruby_status([script], '', '[ruby-core:81016] [Bug #13526]')
  end

  def test_autoload_private_constant
    Dir.mktmpdir('autoload') do |tmpdir|
      File.write(tmpdir+"/zzz.rb", "#{<<~"begin;"}\n#{<<~'end;'}")
      begin;
        class AutoloadTest
          ZZZ = :ZZZ
          private_constant :ZZZ
        end
      end;
      assert_separately(%W[-I #{tmpdir}], "#{<<-"begin;"}\n#{<<-'end;'}")
      bug = '[ruby-core:85516] [Bug #14469]'
      begin;
        class AutoloadTest
          autoload :ZZZ, "zzz.rb"
        end
        assert_raise(NameError, bug) {AutoloadTest::ZZZ}
      end;
    end
  end

  def test_autoload_deprecate_constant
    Dir.mktmpdir('autoload') do |tmpdir|
      File.write(tmpdir+"/zzz.rb", "#{<<~"begin;"}\n#{<<~'end;'}")
      begin;
        class AutoloadTest
          ZZZ = :ZZZ
          deprecate_constant :ZZZ
        end
      end;
      assert_separately(%W[-I #{tmpdir}], "#{<<-"begin;"}\n#{<<-'end;'}")
      bug = '[ruby-core:85516] [Bug #14469]'
      begin;
        class AutoloadTest
          autoload :ZZZ, "zzz.rb"
        end
        assert_warning(/ZZZ is deprecated/, bug) {AutoloadTest::ZZZ}
      end;
    end
  end

  def add_autoload(path)
    (@autoload_paths ||= []) << path
    ::Object.class_eval {autoload(:AutoloadTest, path)}
  end

  def remove_autoload_constant
    $".replace($" - @autoload_paths)
    ::Object.class_eval {remove_const(:AutoloadTest)}
  end
end
