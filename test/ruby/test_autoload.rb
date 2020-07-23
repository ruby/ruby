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
      tmpfile2 = tmpdir + '/bar.rb'
      a = Module.new do
        autoload :X, tmpfile
        autoload :Y, tmpfile2
      end
      b = Module.new do
        include a
      end
      assert_equal(true, a.const_defined?(:X))
      assert_equal(true, b.const_defined?(:X))
      assert_equal(tmpfile, a.autoload?(:X), bug4565)
      assert_equal(tmpfile, b.autoload?(:X), bug4565)
      assert_equal(tmpfile, a.autoload?(:X, false))
      assert_equal(tmpfile, a.autoload?(:X, nil))
      assert_nil(b.autoload?(:X, false))
      assert_nil(b.autoload?(:X, nil))
      assert_equal(true, a.const_defined?("Y"))
      assert_equal(true, b.const_defined?("Y"))
      assert_equal(tmpfile2, a.autoload?("Y"))
      assert_equal(tmpfile2, b.autoload?("Y"))
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
              autoload :C, 'test-ruby-core-69206'
            end
          end
        END

        File.write("test-ruby-core-69206.rb", 'module A; class C; end; end')
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
      File.write(tmpdir+"/test-bug-14469.rb", "#{<<~"begin;"}\n#{<<~'end;'}")
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
          autoload :ZZZ, "test-bug-14469.rb"
        end
        assert_raise(NameError, bug) {AutoloadTest::ZZZ}
      end;
    end
  end

  def test_autoload_deprecate_constant
    Dir.mktmpdir('autoload') do |tmpdir|
      File.write(tmpdir+"/test-bug-14469.rb", "#{<<~"begin;"}\n#{<<~'end;'}")
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
          autoload :ZZZ, "test-bug-14469.rb"
        end
        assert_warning(/ZZZ is deprecated/, bug) {AutoloadTest::ZZZ}
      end;
    end
  end

  def test_autoload_private_constant_before_autoload
    Dir.mktmpdir('autoload') do |tmpdir|
      File.write(tmpdir+"/test-bug-11055.rb", "#{<<~"begin;"}\n#{<<~'end;'}")
      begin;
        class AutoloadTest
          ZZZ = :ZZZ
        end
      end;
      assert_separately(%W[-I #{tmpdir}], "#{<<-"begin;"}\n#{<<-'end;'}")
      bug = '[Bug #11055]'
      begin;
        class AutoloadTest
          autoload :ZZZ, "test-bug-11055.rb"
          private_constant :ZZZ
          ZZZ
        end
        assert_raise(NameError, bug) {AutoloadTest::ZZZ}
      end;
      assert_separately(%W[-I #{tmpdir}], "#{<<-"begin;"}\n#{<<-'end;'}")
      bug = '[Bug #11055]'
      begin;
        class AutoloadTest
          autoload :ZZZ, "test-bug-11055.rb"
          private_constant :ZZZ
        end
        assert_raise(NameError, bug) {AutoloadTest::ZZZ}
      end;
    end
  end

  def test_autoload_deprecate_constant_before_autoload
    Dir.mktmpdir('autoload') do |tmpdir|
      File.write(tmpdir+"/test-bug-11055.rb", "#{<<~"begin;"}\n#{<<~'end;'}")
      begin;
        class AutoloadTest
          ZZZ = :ZZZ
        end
      end;
      assert_separately(%W[-I #{tmpdir}], "#{<<-"begin;"}\n#{<<-'end;'}")
      bug = '[Bug #11055]'
      begin;
        class AutoloadTest
          autoload :ZZZ, "test-bug-11055.rb"
          deprecate_constant :ZZZ
        end
        assert_warning(/ZZZ is deprecated/, bug) {class AutoloadTest; ZZZ; end}
        assert_warning(/ZZZ is deprecated/, bug) {AutoloadTest::ZZZ}
      end;
      assert_separately(%W[-I #{tmpdir}], "#{<<-"begin;"}\n#{<<-'end;'}")
      bug = '[Bug #11055]'
      begin;
        class AutoloadTest
          autoload :ZZZ, "test-bug-11055.rb"
          deprecate_constant :ZZZ
        end
        assert_warning(/ZZZ is deprecated/, bug) {AutoloadTest::ZZZ}
      end;
    end
  end

  def test_autoload_fork
    EnvUtil.default_warning do
      Tempfile.create(['autoload', '.rb']) {|file|
        file.puts 'sleep 0.3; class AutoloadTest; end'
        file.close
        add_autoload(file.path)
        begin
          thrs = []
          3.times do
            thrs << Thread.new { AutoloadTest && nil }
            thrs << Thread.new { fork { AutoloadTest } }
          end
          thrs.each(&:join)
          thrs.each do |th|
            pid = th.value or next
            _, status = Process.waitpid2(pid)
            assert_predicate status, :success?
          end
        ensure
          remove_autoload_constant
          assert_nil $!, '[ruby-core:86410] [Bug #14634]'
        end
      }
    end
  end if Process.respond_to?(:fork)

  def test_autoload_same_file
    Dir.mktmpdir('autoload') do |tmpdir|
      File.write("#{tmpdir}/test-bug-14742.rb", "#{<<~'begin;'}\n#{<<~'end;'}")
      begin;
        module Foo; end
        module Bar; end
      end;
      3.times do # timing-dependent, needs a few times to hit [Bug #14742]
        assert_separately(%W[-I #{tmpdir}], "#{<<-'begin;'}\n#{<<-'end;'}")
        begin;
          autoload :Foo, 'test-bug-14742'
          autoload :Bar, 'test-bug-14742'
          t1 = Thread.new do Foo end
          t2 = Thread.new do Bar end
          t1.join
          t2.join
          bug = '[ruby-core:86935] [Bug #14742]'
          assert_instance_of Module, t1.value, bug
          assert_instance_of Module, t2.value, bug
        end;
      end
    end
  end

  def test_autoload_same_file_with_raise
    Dir.mktmpdir('autoload') do |tmpdir|
      File.write("#{tmpdir}/test-bug-16177.rb", "#{<<~'begin;'}\n#{<<~'end;'}")
      begin;
        raise '[ruby-core:95055] [Bug #16177]'
      end;
      assert_raise(RuntimeError, '[ruby-core:95055] [Bug #16177]') do
        assert_separately(%W[-I #{tmpdir}], "#{<<-'begin;'}\n#{<<-'end;'}")
        begin;
          autoload :Foo, 'test-bug-16177'
          autoload :Bar, 'test-bug-16177'
          t1 = Thread.new do Foo end
          t2 = Thread.new do Bar end
          t1.join
          t2.join
        end;
      end
    end
  end

  def test_source_location
    klass = self.class
    bug = "Bug16764"
    Dir.mktmpdir('autoload') do |tmpdir|
      path = "#{tmpdir}/test-#{bug}.rb"
      File.write(path, "#{klass}::#{bug} = __FILE__\n")
      klass.autoload(:Bug16764, path)
      assert_equal [__FILE__, __LINE__-1], klass.const_source_location(bug)
      assert_equal path, klass.const_get(bug)
      assert_equal [path, 1], klass.const_source_location(bug)
    end
  end

  def test_no_leak
    assert_no_memory_leak([], '', <<~'end;', 'many autoloads', timeout: 60)
      200000.times do |i|
        m = Module.new
        m.instance_eval do
          autoload :Foo, 'x'
          autoload :Bar, i.to_s
        end
      end
    end;
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
