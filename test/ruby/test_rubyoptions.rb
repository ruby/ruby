# -*- coding: us-ascii -*-
require 'test/unit'

require 'timeout'
require 'tmpdir'
require 'tempfile'
require_relative '../lib/jit_support'

class TestRubyOptions < Test::Unit::TestCase
  def self.rjit_enabled? = defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?
  def self.yjit_enabled? = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

  # Here we're defining our own RUBY_DESCRIPTION without "+PRISM". We do this
  # here so that the various tests that reference RUBY_DESCRIPTION don't have to
  # worry about it. The flag itself is tested in its own test.
  RUBY_DESCRIPTION =
    if EnvUtil.invoke_ruby(["-v"], "", true, false)[0].include?("+PRISM")
      ::RUBY_DESCRIPTION
    else
      ::RUBY_DESCRIPTION.sub(/\+PRISM /, '')
    end

  NO_JIT_DESCRIPTION =
    if rjit_enabled?
      RUBY_DESCRIPTION.sub(/\+RJIT /, '')
    elsif yjit_enabled?
      RUBY_DESCRIPTION.sub(/\+YJIT( (dev|dev_nodebug|stats))? /, '')
    else
      RUBY_DESCRIPTION
    end

  def write_file(filename, content)
    File.open(filename, "w") {|f|
      f << content
    }
  end

  def with_tmpchdir
    Dir.mktmpdir {|d|
      d = File.realpath(d)
      Dir.chdir(d) {
        yield d
      }
    }
  end

  def test_source_file
    assert_in_out_err([], "", [], [])
  end

  def test_usage
    assert_in_out_err(%w(-h)) do |r, e|
      assert_operator(r.size, :<=, 25)
      longer = r[1..-1].select {|x| x.size > 80}
      assert_equal([], longer)
      assert_equal([], e)
    end
  end

  def test_usage_long
    assert_in_out_err(%w(--help)) do |r, e|
      longer = r[1..-1].select {|x| x.size > 80}
      assert_equal([], longer)
      assert_equal([], e)
    end
  end

  def test_option_variables
    assert_in_out_err(["-e", 'p [$-p, $-l, $-a]']) do |r, e|
      assert_equal(["[false, false, false]"], r)
      assert_equal([], e)
    end

    assert_in_out_err(%w(-p -l -a -e) + ['p [$-p, $-l, $-a]'],
                      "foo\nbar\nbaz") do |r, e|
      assert_equal(
        [ '[true, true, true]', 'foo',
          '[true, true, true]', 'bar',
          '[true, true, true]', 'baz' ], r)
      assert_equal([], e)
    end
  end

  def test_backtrace_limit
    assert_in_out_err(%w(--backtrace-limit), "", [], /missing argument for --backtrace-limit/)
    assert_in_out_err(%w(--backtrace-limit= 1), "", [], /missing argument for --backtrace-limit/)
    assert_in_out_err(%w(--backtrace-limit=-2), "", [], /wrong limit for backtrace length/)
    code = 'def f(n);n > 0 ? f(n-1) : raise;end;f(5)'
    assert_in_out_err(%w(--backtrace-limit=1), code, [],
                      [/.*unhandled exception\n/, /^\tfrom .*\n/,
                       /^\t \.{3} \d+ levels\.{3}\n/])
    assert_in_out_err(%w(--backtrace-limit=3), code, [],
                      [/.*unhandled exception\n/, *[/^\tfrom .*\n/]*3,
                       /^\t \.{3} \d+ levels\.{3}\n/])
    assert_kind_of(Integer, Thread::Backtrace.limit)
    assert_in_out_err(%w(--backtrace-limit=1), "p Thread::Backtrace.limit", ['1'], [])
    assert_in_out_err(%w(--backtrace-limit 1), "p Thread::Backtrace.limit", ['1'], [])
    env = {"RUBYOPT" => "--backtrace-limit=5"}
    assert_in_out_err([env], "p Thread::Backtrace.limit", ['5'], [])
    assert_in_out_err([env, "--backtrace-limit=1"], "p Thread::Backtrace.limit", ['1'], [])
    assert_in_out_err([env, "--backtrace-limit=-1"], "p Thread::Backtrace.limit", ['-1'], [])
    assert_in_out_err([env, "--backtrace-limit=3", "--backtrace-limit=1"],
                      "p Thread::Backtrace.limit", ['1'], [])
    assert_in_out_err([{"RUBYOPT" => "--backtrace-limit=5 --backtrace-limit=3"}],
                      "p Thread::Backtrace.limit", ['3'], [])
    long_max = RbConfig::LIMITS["LONG_MAX"]
    assert_in_out_err(%W(--backtrace-limit=#{long_max}), "p Thread::Backtrace.limit",
                      ["#{long_max}"], [])
  end

  def test_warning
    save_rubyopt = ENV.delete('RUBYOPT')
    assert_in_out_err(%w(-W0 -e) + ['p $-W'], "", %w(0), [])
    assert_in_out_err(%w(-W1 -e) + ['p $-W'], "", %w(1), [])
    assert_in_out_err(%w(-Wx -e) + ['p $-W'], "", %w(2), [])
    assert_in_out_err(%w(-W -e) + ['p $-W'], "", %w(2), [])
    assert_in_out_err(%w(-We) + ['p $-W'], "", %w(2), [])
    assert_in_out_err(%w(-w -W0 -e) + ['p $-W'], "", %w(0), [])
    assert_in_out_err(%w(-W:deprecated -e) + ['p Warning[:deprecated]'], "", %w(true), [])
    assert_in_out_err(%w(-W:no-deprecated -e) + ['p Warning[:deprecated]'], "", %w(false), [])
    assert_in_out_err(%w(-W:experimental -e) + ['p Warning[:experimental]'], "", %w(true), [])
    assert_in_out_err(%w(-W:no-experimental -e) + ['p Warning[:experimental]'], "", %w(false), [])
    assert_in_out_err(%w(-W -e) + ['p Warning[:performance]'], "", %w(false), [])
    assert_in_out_err(%w(-W:performance -e) + ['p Warning[:performance]'], "", %w(true), [])
    assert_in_out_err(%w(-W:qux), "", [], /unknown warning category: `qux'/)
    assert_in_out_err(%w(-w -e) + ['p Warning[:deprecated]'], "", %w(true), [])
    assert_in_out_err(%w(-W -e) + ['p Warning[:deprecated]'], "", %w(true), [])
    assert_in_out_err(%w(-We) + ['p Warning[:deprecated]'], "", %w(true), [])
    assert_in_out_err(%w(-e) + ['p Warning[:deprecated]'], "", %w(false), [])
    assert_in_out_err(%w(-w -e) + ['p Warning[:performance]'], "", %w(false), [])
    assert_in_out_err(%w(-W -e) + ['p Warning[:performance]'], "", %w(false), [])
    code = 'puts "#{$VERBOSE}:#{Warning[:deprecated]}:#{Warning[:experimental]}:#{Warning[:performance]}"'
    Tempfile.create(["test_ruby_test_rubyoption", ".rb"]) do |t|
      t.puts code
      t.close
      assert_in_out_err(["-r#{t.path}", '-e', code], "", %w(false:false:true:false false:false:true:false), [])
      assert_in_out_err(["-r#{t.path}", '-w', '-e', code], "", %w(true:true:true:false true:true:true:false), [])
      assert_in_out_err(["-r#{t.path}", '-W:deprecated', '-e', code], "", %w(false:true:true:false false:true:true:false), [])
      assert_in_out_err(["-r#{t.path}", '-W:no-experimental', '-e', code], "", %w(false:false:false:false false:false:false:false), [])
      assert_in_out_err(["-r#{t.path}", '-W:performance', '-e', code], "", %w(false:false:true:true false:false:true:true), [])
    end
  ensure
    ENV['RUBYOPT'] = save_rubyopt
  end

  def test_debug
    assert_in_out_err(["-de", "p $DEBUG"], "", %w(true), [])

    assert_in_out_err(["--debug", "-e", "p $DEBUG"],
                      "", %w(true), [])

    assert_in_out_err(["--debug-", "-e", "p $DEBUG"], "", %w(), /invalid option --debug-/)
  end

  q = Regexp.method(:quote)
  VERSION_PATTERN =
    case RUBY_ENGINE
    when 'jruby'
      /^jruby #{q[RUBY_ENGINE_VERSION]} \(#{q[RUBY_VERSION]}\).*? \[#{
        q[RbConfig::CONFIG["host_os"]]}-#{q[RbConfig::CONFIG["host_cpu"]]}\]$/
    else
      /^ruby #{q[RUBY_VERSION]}(?:[p ]|dev|rc).*? (\+PRISM )?\[#{q[RUBY_PLATFORM]}\]$/
    end
  private_constant :VERSION_PATTERN

  VERSION_PATTERN_WITH_RJIT =
    case RUBY_ENGINE
    when 'ruby'
      /^ruby #{q[RUBY_VERSION]}(?:[p ]|dev|rc).*? \+RJIT (\+MN )?(\+PRISM )?\[#{q[RUBY_PLATFORM]}\]$/
    else
      VERSION_PATTERN
    end
  private_constant :VERSION_PATTERN_WITH_RJIT

  def test_verbose
    assert_in_out_err([{'RUBY_YJIT_ENABLE' => nil}, "-vve", ""]) do |r, e|
      assert_match(VERSION_PATTERN, r[0])
      if self.class.rjit_enabled? && !JITSupport.rjit_force_enabled?
        assert_equal(NO_JIT_DESCRIPTION, r[0])
      elsif self.class.yjit_enabled? && !JITSupport.yjit_force_enabled?
        assert_equal(NO_JIT_DESCRIPTION, r[0])
      else
        assert_equal(RUBY_DESCRIPTION, r[0])
      end
      assert_equal([], e)
    end

    assert_in_out_err(%w(--verbose -e) + ["p $VERBOSE"], "", %w(true), [])

    assert_in_out_err(%w(--verbose), "", [], [])
  end

  def test_copyright
    assert_in_out_err(%w(--copyright), "",
                      /^ruby - Copyright \(C\) 1993-\d+ Yukihiro Matsumoto$/, [])

    assert_in_out_err(%w(--verbose -e) + ["p $VERBOSE"], "", %w(true), [])
  end

  def test_enable
    if JITSupport.yjit_supported?
      assert_in_out_err(%w(--enable all -e) + [""], "", [], [])
      assert_in_out_err(%w(--enable-all -e) + [""], "", [], [])
      assert_in_out_err(%w(--enable=all -e) + [""], "", [], [])
    elsif JITSupport.rjit_supported?
      # Avoid failing tests by RJIT warnings
      assert_in_out_err(%w(--enable all --disable rjit -e) + [""], "", [], [])
      assert_in_out_err(%w(--enable-all --disable-rjit -e) + [""], "", [], [])
      assert_in_out_err(%w(--enable=all --disable=rjit -e) + [""], "", [], [])
    end
    assert_in_out_err(%w(--enable foobarbazqux -e) + [""], "", [],
                      /unknown argument for --enable: `foobarbazqux'/)
    assert_in_out_err(%w(--enable), "", [], /missing argument for --enable/)
  end

  def test_disable
    assert_in_out_err(%w(--disable all -e) + [""], "", [], [])
    assert_in_out_err(%w(--disable-all -e) + [""], "", [], [])
    assert_in_out_err(%w(--disable=all -e) + [""], "", [], [])
    assert_in_out_err(%w(--disable foobarbazqux -e) + [""], "", [],
                      /unknown argument for --disable: `foobarbazqux'/)
    assert_in_out_err(%w(--disable), "", [], /missing argument for --disable/)
    assert_in_out_err(%w(-e) + ['p defined? Gem'], "", ["nil"], [])
    assert_in_out_err(%w(--disable-did_you_mean -e) + ['p defined? DidYouMean'], "", ["nil"], [])
    assert_in_out_err(%w(-e) + ['p defined? DidYouMean'], "", ["nil"], [])
  end

  def test_kanji
    assert_in_out_err(%w(-KU), "p '\u3042'") do |r, e|
      assert_equal("\"\u3042\"", r.join('').force_encoding(Encoding::UTF_8))
    end
    line = '-eputs"\xc2\xa1".encoding'
    env = {'RUBYOPT' => nil}
    assert_in_out_err([env, '-Ke', line], "", ["EUC-JP"], [])
    assert_in_out_err([env, '-KE', line], "", ["EUC-JP"], [])
    assert_in_out_err([env, '-Ks', line], "", ["Windows-31J"], [])
    assert_in_out_err([env, '-KS', line], "", ["Windows-31J"], [])
    assert_in_out_err([env, '-Ku', line], "", ["UTF-8"], [])
    assert_in_out_err([env, '-KU', line], "", ["UTF-8"], [])
    assert_in_out_err([env, '-Kn', line], "", ["ASCII-8BIT"], [])
    assert_in_out_err([env, '-KN', line], "", ["ASCII-8BIT"], [])
    assert_in_out_err([env, '-wKe', line], "", ["EUC-JP"], /-K/)
  end

  def test_version
    env = { 'RUBY_YJIT_ENABLE' => nil } # unset in children
    assert_in_out_err([env, '--version']) do |r, e|
      assert_match(VERSION_PATTERN, r[0])
      if ENV['RUBY_YJIT_ENABLE'] == '1'
        assert_equal(NO_JIT_DESCRIPTION, r[0])
      elsif self.class.rjit_enabled? || self.class.yjit_enabled? # checking -D(M|Y)JIT_FORCE_ENABLE
        assert_equal(EnvUtil.invoke_ruby(['-e', 'print RUBY_DESCRIPTION'], '', true).first, r[0])
      else
        assert_equal(RUBY_DESCRIPTION, r[0])
      end
      assert_equal([], e)
    end
  end

  def test_rjit_disabled_version
    return unless JITSupport.rjit_supported?
    return if JITSupport.yjit_force_enabled?

    env = { 'RUBY_YJIT_ENABLE' => nil } # unset in children
    [
      %w(--version --rjit --disable=rjit),
      %w(--version --enable=rjit --disable=rjit),
      %w(--version --enable-rjit --disable-rjit),
    ].each do |args|
      assert_in_out_err([env] + args) do |r, e|
        assert_match(VERSION_PATTERN, r[0])
        assert_match(NO_JIT_DESCRIPTION, r[0])
        assert_equal([], e)
      end
    end
  end

  def test_rjit_version
    return unless JITSupport.rjit_supported?
    return if JITSupport.yjit_force_enabled?

    env = { 'RUBY_YJIT_ENABLE' => nil } # unset in children
    [
      %w(--version --rjit),
      %w(--version --enable=rjit),
      %w(--version --enable-rjit),
    ].each do |args|
      assert_in_out_err([env] + args) do |r, e|
        assert_match(VERSION_PATTERN_WITH_RJIT, r[0])
        if JITSupport.rjit_force_enabled?
          assert_equal(RUBY_DESCRIPTION, r[0])
        else
          assert_equal(EnvUtil.invoke_ruby([env, '--rjit', '-e', 'print RUBY_DESCRIPTION'], '', true).first, r[0])
        end
        assert_equal([], e)
      end
    end
  end

  PRISM_WARNING = /compiler based on the Prism parser is currently experimental/

  def test_parser_flag
    assert_in_out_err(%w(--parser=prism -e) + ["puts :hi"], "", %w(hi), PRISM_WARNING)

    assert_in_out_err(%w(--parser=parse.y -e) + ["puts :hi"], "", %w(hi), [])
    assert_norun_with_rflag('--parser=parse.y', '--version', "")

    assert_in_out_err(%w(--parser=notreal -e) + ["puts :hi"], "", [], /unknown parser notreal/)

    assert_in_out_err(%w(--parser=prism --version), "", /\+PRISM/, PRISM_WARNING)
  end

  def test_eval
    assert_in_out_err(%w(-e), "", [], /no code specified for -e \(RuntimeError\)/)
  end

  def test_require
    require "pp"
    assert_in_out_err(%w(-r pp -e) + ["pp 1"], "", %w(1), [])
    assert_in_out_err(%w(-rpp -e) + ["pp 1"], "", %w(1), [])
    assert_in_out_err(%w(-ep\ 1 -r), "", %w(1), [])
    assert_in_out_err(%w(-r), "", [], [])
  rescue LoadError
  end

  def test_include
    d = Dir.tmpdir
    assert_in_out_err(["-I" + d, "-e", ""], "", [], [])
    assert_in_out_err(["-I", d, "-e", ""], "", [], [])
  end

  def test_separator
    assert_in_out_err(%w(-000 -e) + ["print gets"], "foo\nbar\0baz", %W(foo bar\0baz), [])

    assert_in_out_err(%w(-0141 -e) + ["print gets"], "foo\nbar\0baz", %w(foo ba), [])

    assert_in_out_err(%w(-0e) + ["print gets"], "foo\nbar\0baz", %W(foo bar\0), [])

    assert_in_out_err(%w(-00 -e) + ["p gets, gets"], "foo\nbar\n\nbaz\nzot\n\n\n", %w("foo\nbar\n\n" "baz\nzot\n\n"), [])

    assert_in_out_err(%w(-00 -e) + ["p gets, gets"], "foo\nbar\n\n\n\nbaz\n", %w("foo\nbar\n\n" "baz\n"), [])
  end

  def test_autosplit
    assert_in_out_err(%w(-W0 -an -F: -e) + ["p $F"], "foo:bar:baz\nqux:quux:quuux\n",
                      ['["foo", "bar", "baz\n"]', '["qux", "quux", "quuux\n"]'], [])
  end

  def test_chdir
    omit "not working on MinGW" if /mingw/ =~ RUBY_PLATFORM
    assert_in_out_err(%w(-C), "", [], /Can't chdir/)

    assert_in_out_err(%w(-C test_ruby_test_rubyoptions_foobarbazqux), "", [], /Can't chdir/)

    d = Dir.tmpdir
    assert_in_out_err(["-C", d, "-e", "puts Dir.pwd"]) do |r, e|
      assert_file.identical?(r.join(''), d)
      assert_equal([], e)
    end

    Dir.mktmpdir(d) do |base|
      # "test" in Japanese and N'Ko
      test = base + "/\u{30c6 30b9 30c8}_\u{7e1 7ca 7dd 7cc 7df 7cd 7eb}"
      Dir.mkdir(test)
      assert_in_out_err(["-C", base, "-C", File.basename(test), "-e", "puts Dir.pwd"]) do |r, e|
        assert_file.identical?(r.join(''), test)
        assert_equal([], e)
      end
      Dir.rmdir(test)
    end
  end

  def test_yydebug
    assert_in_out_err(["-ye", ""]) do |r, e|
      assert_not_equal([], r)
      assert_equal([], e)
    end

    assert_in_out_err(%w(--yydebug -e) + [""]) do |r, e|
      assert_not_equal([], r)
      assert_equal([], e)
    end
  end

  def test_encoding
    assert_in_out_err(%w(--encoding), "", [], /missing argument for --encoding/)

    assert_in_out_err(%w(--encoding test_ruby_test_rubyoptions_foobarbazqux), "", [],
                      /unknown encoding name - test_ruby_test_rubyoptions_foobarbazqux \(RuntimeError\)/)

    if /mswin|mingw|aix|android/ =~ RUBY_PLATFORM &&
      (str = "\u3042".force_encoding(Encoding.find("external"))).valid_encoding?
      # This result depends on locale because LANG=C doesn't affect locale
      # on Windows.
      # On AIX, the source encoding of stdin with LANG=C is ISO-8859-1,
      # which allows \u3042.
      out, err = [str], []
    else
      out, err = [], /invalid multibyte char/
    end
    assert_in_out_err(%w(-Eutf-8), "puts '\u3042'", out, err)
    assert_in_out_err(%w(--encoding utf-8), "puts '\u3042'", out, err)
  end

  def test_syntax_check
    assert_in_out_err(%w(-cw -e a=1+1 -e !a), "", ["Syntax OK"], [])
    assert_in_out_err(%w(-cw -e break), "", [], ["-e:1: Invalid break", :*])
    assert_in_out_err(%w(-cw -e next), "", [], ["-e:1: Invalid next", :*])
    assert_in_out_err(%w(-cw -e redo), "", [], ["-e:1: Invalid redo", :*])
    assert_in_out_err(%w(-cw -e retry), "", [], ["-e:1: Invalid retry", :*])
    assert_in_out_err(%w(-cw -e yield), "", [], ["-e:1: Invalid yield", :*])
    assert_in_out_err(%w(-cw -e begin -e break -e end), "", [], ["-e:2: Invalid break", :*])
    assert_in_out_err(%w(-cw -e begin -e next -e end), "", [], ["-e:2: Invalid next", :*])
    assert_in_out_err(%w(-cw -e begin -e redo -e end), "", [], ["-e:2: Invalid redo", :*])
    assert_in_out_err(%w(-cw -e begin -e retry -e end), "", [], ["-e:2: Invalid retry", :*])
    assert_in_out_err(%w(-cw -e begin -e yield -e end), "", [], ["-e:2: Invalid yield", :*])
    assert_in_out_err(%w(-cw -e !defined?(break)), "", ["Syntax OK"], [])
    assert_in_out_err(%w(-cw -e !defined?(next)), "", ["Syntax OK"], [])
    assert_in_out_err(%w(-cw -e !defined?(redo)), "", ["Syntax OK"], [])
    assert_in_out_err(%w(-cw -e !defined?(retry)), "", ["Syntax OK"], [])
    assert_in_out_err(%w(-cw -e !defined?(yield)), "", ["Syntax OK"], [])
    assert_in_out_err(%w(-n -cw -e break), "", ["Syntax OK"], [])
    assert_in_out_err(%w(-n -cw -e next), "", ["Syntax OK"], [])
    assert_in_out_err(%w(-n -cw -e redo), "", ["Syntax OK"], [])
  end

  def test_invalid_option
    assert_in_out_err(%w(--foobarbazqux), "", [], /invalid option --foobarbazqux/)

    assert_in_out_err(%W(-\r -e) + [""], "", [], [])

    assert_in_out_err(%W(-\rx), "", [], /invalid option -[\r\n]  \(-h will show valid options\) \(RuntimeError\)/)

    assert_in_out_err(%W(-\x01), "", [], /invalid option -\x01  \(-h will show valid options\) \(RuntimeError\)/)

    assert_in_out_err(%w(-Z), "", [], /invalid option -Z  \(-h will show valid options\) \(RuntimeError\)/)
  end

  def test_rubyopt
    rubyopt_orig = ENV['RUBYOPT']

    ENV['RUBYOPT'] = ' - -'
    assert_in_out_err([], "", [], [])

    ENV['RUBYOPT'] = '-e "p 1"'
    assert_in_out_err([], "", [], /invalid switch in RUBYOPT: -e \(RuntimeError\)/)

    ENV['RUBYOPT'] = '-Eus-ascii -KN'
    assert_in_out_err(%w(-Eutf-8 -KU), "p '\u3042'") do |r, e|
      assert_equal("\"\u3042\"", r.join.force_encoding(Encoding::UTF_8))
      assert_equal([], e)
    end

    ENV['RUBYOPT'] = '-w'
    assert_in_out_err(%w(), "p $VERBOSE", ["true"])
    assert_in_out_err(%w(-W1), "p $VERBOSE", ["false"])
    assert_in_out_err(%w(-W0), "p $VERBOSE", ["nil"])
    assert_in_out_err(%w(), "p Warning[:deprecated]", ["true"])
    assert_in_out_err(%w(-W0), "p Warning[:deprecated]", ["false"])
    assert_in_out_err(%w(-W1), "p Warning[:deprecated]", ["false"])
    assert_in_out_err(%w(-W2), "p Warning[:deprecated]", ["true"])
    ENV['RUBYOPT'] = '-W:deprecated'
    assert_in_out_err(%w(), "p Warning[:deprecated]", ["true"])
    ENV['RUBYOPT'] = '-W:no-deprecated'
    assert_in_out_err(%w(), "p Warning[:deprecated]", ["false"])
    ENV['RUBYOPT'] = '-W:experimental'
    assert_in_out_err(%w(), "p Warning[:experimental]", ["true"])
    ENV['RUBYOPT'] = '-W:no-experimental'
    assert_in_out_err(%w(), "p Warning[:experimental]", ["false"])
    ENV['RUBYOPT'] = '-W:qux'
    assert_in_out_err(%w(), "", [], /unknown warning category: `qux'/)

    ENV['RUBYOPT'] = 'w'
    assert_in_out_err(%w(), "p $VERBOSE", ["true"])
  ensure
    ENV['RUBYOPT'] = rubyopt_orig
  end

  def test_search
    rubypath_orig = ENV['RUBYPATH']
    path_orig = ENV['PATH']

    Tempfile.create(["test_ruby_test_rubyoption", ".rb"]) {|t|
      t.puts "p 1"
      t.close

      @verbose = $VERBOSE
      $VERBOSE = nil

      path, name = File.split(t.path)

      ENV['PATH'] = (path_orig && RbConfig::CONFIG['LIBPATHENV'] == 'PATH') ?
          [path, path_orig].join(File::PATH_SEPARATOR) : path
      assert_in_out_err(%w(-S) + [name], "", %w(1), [])
      ENV['PATH'] = path_orig

      ENV['RUBYPATH'] = path
      assert_in_out_err(%w(-S) + [name], "", %w(1), [])
    }

  ensure
    if rubypath_orig
      ENV['RUBYPATH'] = rubypath_orig
    else
      ENV.delete('RUBYPATH')
    end
    if path_orig
      ENV['PATH'] = path_orig
    else
      ENV.delete('PATH')
    end
    $VERBOSE = @verbose
  end

  def test_shebang
    assert_in_out_err([], "#! /test_r_u_b_y_test_r_u_b_y_options_foobarbazqux\r\np 1\r\n",
                      [], /: no Ruby script found in input/)

    assert_in_out_err([], "#! /test_r_u_b_y_test_r_u_b_y_options_foobarbazqux -foo -bar\r\np 1\r\n",
                      [], /: no Ruby script found in input/)

    warning = /mswin|mingw/ =~ RUBY_PLATFORM ? [] : /shebang line ending with \\r/
    assert_in_out_err([{'RUBYOPT' => nil}], "#!ruby -KU -Eutf-8\r\np \"\u3042\"\r\n",
                      ["\"\u3042\""], warning,
                      encoding: Encoding::UTF_8)

    bug4118 = '[ruby-dev:42680]'
    assert_in_out_err(%w[], "#!/bin/sh\n""#!shebang\n""#!ruby\n""puts __LINE__\n",
                      %w[4], [], bug4118)
    assert_in_out_err(%w[-x], "#!/bin/sh\n""#!shebang\n""#!ruby\n""puts __LINE__\n",
                      %w[4], [], bug4118)

    assert_ruby_status(%w[], "#! ruby -- /", '[ruby-core:82267] [Bug #13786]')

    assert_ruby_status(%w[], "#!")
    assert_in_out_err(%w[-c], "#!", ["Syntax OK"])
  end

  def test_flag_in_shebang
    Tempfile.create(%w"pflag .rb") do |script|
      code = "#!ruby -p"
      script.puts(code)
      script.close
      assert_in_out_err([script.path, script.path], '', [code])
    end
    Tempfile.create(%w"sflag .rb") do |script|
      script.puts("#!ruby -s")
      script.puts("p $abc")
      script.close
      assert_in_out_err([script.path, "-abc=foo"], '', ['"foo"'])
    end
  end

  def test_sflag
    assert_in_out_err(%w(- -abc -def=foo -ghi-jkl -- -xyz),
                      "#!ruby -s\np [$abc, $def, $ghi_jkl, defined?($xyz)]\n",
                      ['[true, "foo", true, nil]'], [])

    assert_in_out_err(%w(- -#), "#!ruby -s\n", [],
                      /invalid name for global variable - -# \(NameError\)/)

    assert_in_out_err(%w(- -#=foo), "#!ruby -s\n", [],
                      /invalid name for global variable - -# \(NameError\)/)
  end

  def test_assignment_in_conditional
    Tempfile.create(["test_ruby_test_rubyoption", ".rb"]) {|t|
      t.puts "if a = 1"
      t.puts "end"
      t.puts "0.times do"
      t.puts "  if b = 2"
      t.puts "    a += b"
      t.puts "  end"
      t.puts "end"
      t.flush
      warning = ' warning: found `= literal\' in conditional, should be =='
      err = ["#{t.path}:1:#{warning}",
             "#{t.path}:4:#{warning}",
            ]
      bug2136 = '[ruby-dev:39363]'
      assert_in_out_err(["-w", t.path], "", [], err, bug2136)
      assert_in_out_err(["-wr", t.path, "-e", ""], "", [], err, bug2136)

      t.rewind
      t.truncate(0)
      t.puts "if a = ''; end"
      t.puts "if a = []; end"
      t.puts "if a = [1]; end"
      t.puts "if a = [a]; end"
      t.puts "if a = {}; end"
      t.puts "if a = {1=>2}; end"
      t.puts "if a = {3=>a}; end"
      t.flush
      err = ["#{t.path}:1:#{warning}",
             "#{t.path}:2:#{warning}",
             "#{t.path}:3:#{warning}",
             "#{t.path}:5:#{warning}",
             "#{t.path}:6:#{warning}",
            ]
      feature4299 = '[ruby-dev:43083]'
      assert_in_out_err(["-w", t.path], "", [], err, feature4299)
      assert_in_out_err(["-wr", t.path, "-e", ""], "", [], err, feature4299)
    }
  end

  def test_indentation_check
    all_assertions do |a|
      Tempfile.create(["test_ruby_test_rubyoption", ".rb"]) do |t|
        [
          "begin", "if false", "for _ in []", "while false",
          "def foo", "class X", "module M",
          ["-> do", "end"], ["-> {", "}"],
          ["if false;", "else ; end"],
          ["if false;", "elsif false ; end"],
          ["begin", "rescue ; end"],
          ["begin rescue", "else ; end"],
          ["begin", "ensure ; end"],
          ["  case nil", "when true; end"],
          ["case nil; when true", "end"],
          ["if false;", "end", "if true\nelse ", "end"],
          ["else", " end", "_ = if true\n"],
          ["begin\n    def f() = nil", "end"],
          ["begin\n    def self.f() = nil", "end"],
        ].each do
          |b, e = 'end', pre = nil, post = nil|
          src = ["#{pre}#{b}\n", " #{e}\n#{post}"]
          k = b[/\A\s*(\S+)/, 1]
          e = e[/\A\s*(\S+)/, 1]
          n = 1 + src[0].count("\n")
          n1 = 1 + (pre ? pre.count("\n") : 0)

          a.for("no directives with #{src}") do
            err = ["#{t.path}:#{n}: warning: mismatched indentations at '#{e}' with '#{k}' at #{n1}"]
            t.rewind
            t.truncate(0)
            t.puts src
            t.flush
            assert_in_out_err(["-w", t.path], "", [], err)
            assert_in_out_err(["-wr", t.path, "-e", ""], "", [], err)
          end

          a.for("false directive with #{src}") do
            t.rewind
            t.truncate(0)
            t.puts "# -*- warn-indent: false -*-"
            t.puts src
            t.flush
            assert_in_out_err(["-w", t.path], "", [], [], '[ruby-core:25442]')
          end

          a.for("false and true directives with #{src}") do
            err = ["#{t.path}:#{n+2}: warning: mismatched indentations at '#{e}' with '#{k}' at #{n1+2}"]
            t.rewind
            t.truncate(0)
            t.puts "# -*- warn-indent: false -*-"
            t.puts "# -*- warn-indent: true -*-"
            t.puts src
            t.flush
            assert_in_out_err(["-w", t.path], "", [], err, '[ruby-core:25442]')
          end

          a.for("false directives after #{src}") do
            t.rewind
            t.truncate(0)
            t.puts "# -*- warn-indent: true -*-"
            t.puts src[0]
            t.puts "# -*- warn-indent: false -*-"
            t.puts src[1]
            t.flush
            assert_in_out_err(["-w", t.path], "", [], [], '[ruby-core:25442]')
          end

          a.for("BOM with #{src}") do
            err = ["#{t.path}:#{n}: warning: mismatched indentations at '#{e}' with '#{k}' at #{n1}"]
            t.rewind
            t.truncate(0)
            t.print "\u{feff}"
            t.puts src
            t.flush
            assert_in_out_err(["-w", t.path], "", [], err)
            assert_in_out_err(["-wr", t.path, "-e", ""], "", [], err)
          end
        end
      end
    end
  end

  def test_notfound
    notexist = "./notexist.rb"
    dir, *rubybin = RbConfig::CONFIG.values_at('bindir', 'RUBY_INSTALL_NAME', 'EXEEXT')
    rubybin = "#{dir}/#{rubybin.join('')}"
    rubybin.tr!('/', '\\') if /mswin|mingw/ =~ RUBY_PLATFORM
    rubybin = Regexp.quote(rubybin)
    pat = Regexp.quote(notexist)
    bug1573 = '[ruby-core:23717]'
    assert_file.not_exist?(notexist)
    assert_in_out_err(["-r", notexist, "-ep"], "", [], /.* -- #{pat} \(LoadError\)/, bug1573)
    assert_in_out_err([notexist], "", [], /#{rubybin}:.* -- #{pat} \(LoadError\)/, bug1573)
  end

  def test_program_name
    ruby = EnvUtil.rubybin
    IO.popen([ruby, '-e', 'print $0']) {|f|
      assert_equal('-e', f.read)
    }
    IO.popen([ruby, '-'], 'r+') {|f|
      f << 'print $0'
      f.close_write
      assert_equal('-', f.read)
    }
    Dir.mktmpdir {|d|
      n1 = File.join(d, 't1')
      open(n1, 'w') {|f| f << 'print $0' }
      IO.popen([ruby, n1]) {|f|
        assert_equal(n1, f.read)
      }
      if File.respond_to? :symlink
        n2 = File.join(d, 't2')
        begin
          File.symlink(n1, n2)
        rescue Errno::EACCES
        else
          IO.popen([ruby, n2]) {|f|
            assert_equal(n2, f.read)
          }
        end
      end
      Dir.chdir(d) {
        n3 = '-e'
        open(n3, 'w') {|f| f << 'print $0' }
        IO.popen([ruby, '--', n3]) {|f|
          assert_equal(n3, f.read)
        }
        n4 = '-'
        IO.popen([ruby, '--', n4], 'r+') {|f|
          f << 'print $0'
          f.close_write
          assert_equal(n4, f.read)
        }
      }
    }
  end

  if /linux|freebsd|netbsd|openbsd|darwin/ =~ RUBY_PLATFORM
    PSCMD = EnvUtil.find_executable("ps", "-o", "command", "-p", $$.to_s) {|out| /ruby/=~out}
    PSCMD&.pop
  end

  def test_set_program_name
    omit "platform dependent feature" unless defined?(PSCMD) and PSCMD

    with_tmpchdir do
      write_file("test-script", "$0 = 'hello world'; /test-script/ =~ Process.argv0 or $0 = 'Process.argv0 changed!'; sleep 60")

      pid = spawn(EnvUtil.rubybin, "test-script")
      ps = nil
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stop = now + 30
      begin
        sleep 0.1
        ps = `#{PSCMD.join(' ')} #{pid}`
        break if /hello world/ =~ ps
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end until Process.wait(pid, Process::WNOHANG) || now > stop
      assert_match(/hello world/, ps)
      assert_operator now, :<, stop
      Process.kill :KILL, pid
      EnvUtil.timeout(5) { Process.wait(pid) }
    end
  end

  def test_setproctitle
    omit "platform dependent feature" unless defined?(PSCMD) and PSCMD

    assert_separately([], "#{<<-"{#"}\n#{<<-'};'}")
    {#
      assert_raise(ArgumentError) do
        Process.setproctitle("hello\0")
      end
    };

    with_tmpchdir do
      write_file("test-script", "$_0 = $0.dup; Process.setproctitle('hello world'); $0 == $_0 or Process.setproctitle('$0 changed!'); sleep 60")

      pid = spawn(EnvUtil.rubybin, "test-script")
      ps = nil
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stop = now + 30
      begin
        sleep 0.1
        ps = `#{PSCMD.join(' ')} #{pid}`
        break if /hello world/ =~ ps
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end until Process.wait(pid, Process::WNOHANG) || now > stop
      assert_match(/hello world/, ps)
      assert_operator now, :<, stop
      Process.kill :KILL, pid
      Timeout.timeout(5) { Process.wait(pid) }
    end
  end

  module SEGVTest
    opts = {}
    unless /mswin|mingw/ =~ RUBY_PLATFORM
      opts[:rlimit_core] = 0
    end
    ExecOptions = opts.freeze

    ExpectedStderrList = [
      %r(
        -e:(?:1:)?\s\[BUG\]\sSegmentation\sfault.*\n
      )x,
      %r(
        #{ Regexp.quote((TestRubyOptions.rjit_enabled? && !JITSupport.rjit_force_enabled?) ? NO_JIT_DESCRIPTION : RUBY_DESCRIPTION) }\n\n
      )x,
      %r(
        (?:--\s(?:.+\n)*\n)?
        --\sControl\sframe\sinformation\s-+\n
        (?:(?:c:.*\n)|(?:^\s+.+\n))*
        \n
      )x,
      %r(
        (?:
        --\sRuby\slevel\sbacktrace\sinformation\s----------------------------------------\n
        (?:-e:1:in\s\`(?:block\sin\s)?<main>\'\n)*
        -e:1:in\s\`kill\'\n
        \n
        )?
      )x,
      %r(
        (?:--\sThreading(?:.+\n)*\n)?
      )x,
      %r(
        (?:--\sMachine(?:.+\n)*\n)?
      )x,
      %r(
        (?:
          --\sC\slevel\sbacktrace\sinformation\s-------------------------------------------\n
          (?:Un(?:expected|supported|known)\s.*\n)*
          (?:(?:.*\s)?\[0x\h+\].*\n|.*:\d+\n)*\n
        )?
      )x,
      %r(
        (?:--\sOther\sruntime\sinformation\s-+\n
          (?:.*\n)*
        )?
      )x,
    ]

    KILL_SELF = "Process.kill :SEGV, $$"
  end

  def assert_segv(args, message=nil, list: SEGVTest::ExpectedStderrList, **opt)
    # We want YJIT to be enabled in the subprocess if it's enabled for us
    # so that the Ruby description matches.
    env = Hash === args.first ? args.shift : {}
    args.unshift("--yjit") if self.class.yjit_enabled?
    env.update({'RUBY_ON_BUG' => nil})
    args.unshift(env)

    test_stdin = ""

    assert_in_out_err(args, test_stdin, //, list, encoding: "ASCII-8BIT",
                      **SEGVTest::ExecOptions, **opt)
  end

  def test_segv_test
    assert_segv(["--disable-gems", "-e", SEGVTest::KILL_SELF])
  end

  def test_segv_loaded_features
    bug7402 = '[ruby-core:49573]'

    status = assert_segv(['-e', "END {#{SEGVTest::KILL_SELF}}",
                          '-e', 'class Bogus; def to_str; exit true; end; end',
                          '-e', '$".clear',
                          '-e', '$".unshift Bogus.new',
                          '-e', '(p $"; abort) unless $".size == 1',
                         ])
    assert_not_predicate(status, :success?, "segv but success #{bug7402}")
  end

  def test_segv_setproctitle
    bug7597 = '[ruby-dev:46786]'
    Tempfile.create(["test_ruby_test_bug7597", ".rb"]) {|t|
      t.write "f" * 100
      t.flush
      assert_segv(["--disable-gems", "-e", "$0=ARGV[0]; #{SEGVTest::KILL_SELF}", t.path], bug7597)
    }
  end

  def assert_crash_report(path, cmd = nil)
    Dir.mktmpdir("ruby_crash_report") do |dir|
      list = SEGVTest::ExpectedStderrList
      if cmd
        FileUtils.mkpath(File.join(dir, File.dirname(cmd)))
        File.write(File.join(dir, cmd), SEGVTest::KILL_SELF+"\n")
        c = Regexp.quote(cmd)
        list = list.map {|re| Regexp.new(re.source.gsub(/^\s*(\(\?:)?\K-e(?=:)/) {c}, re.options)}
      else
        cmd = ['-e', SEGVTest::KILL_SELF]
      end
      status = assert_segv([{"RUBY_CRASH_REPORT"=>path}, *cmd], list: [], chdir: dir)
      reports = Dir.glob("*.log", File::FNM_DOTMATCH, base: dir)
      assert_equal(1, reports.size)
      assert_pattern_list(list, File.read(File.join(dir, reports.first)))
      break status, reports.first
    end
  end

  def test_crash_report
    assert_crash_report("%e.%f.%p.log") do |status, report|
      assert_equal("#{File.basename(EnvUtil.rubybin)}.-e.#{status.pid}.log", report)
    end
  end

  def test_crash_report_script
    assert_crash_report("%e.%f.%p.log", "bug.rb") do |status, report|
      assert_equal("#{File.basename(EnvUtil.rubybin)}.bug.rb.#{status.pid}.log", report)
    end
  end

  def test_crash_report_executable_path
    omit if EnvUtil.rubybin.size > 245
    assert_crash_report("%E.%p.log") do |status, report|
      assert_equal("#{EnvUtil.rubybin.tr('/', '!')}.#{status.pid}.log", report)
    end
  end

  def test_crash_report_script_path
    assert_crash_report("%F.%p.log", "test/bug.rb") do |status, report|
      assert_equal("test!bug.rb.#{status.pid}.log", report)
    end
  end

  def test_crash_report_pipe
    if File.executable?(echo = "/bin/echo")
    elsif /mswin|ming/ =~ RUBY_PLATFORM
      echo = "echo"
    else
      omit "/bin/echo not found"
    end
    env = {"RUBY_CRASH_REPORT"=>"| #{echo} %e:%f:%p", "RUBY_ON_BUG"=>nil}
    assert_in_out_err([env], SEGVTest::KILL_SELF,
                      encoding: "ASCII-8BIT",
                      **SEGVTest::ExecOptions) do |stdout, stderr, status|
      assert_empty(stderr)
      assert_equal(["#{File.basename(EnvUtil.rubybin)}:-:#{status.pid}"], stdout)
    end
  end

  def test_DATA
    Tempfile.create(["test_ruby_test_rubyoption", ".rb"]) {|t|
      t.puts "puts DATA.read.inspect"
      t.puts "__END__"
      t.puts "foo"
      t.puts "bar"
      t.puts "baz"
      t.flush
      assert_in_out_err([t.path], "", %w("foo\\nbar\\nbaz\\n"), [])
    }
  end

  def test_unused_variable
    feature3446 = '[ruby-dev:41620]'
    assert_in_out_err(["-we", "a=1"], "", [], [], feature3446)
    assert_in_out_err(["-we", "def foo\n  a=1\nend"], "", [], ["-e:2: warning: assigned but unused variable - a"], feature3446)
    assert_in_out_err(["-we", "def foo\n  eval('a=1')\nend"], "", [], [], feature3446)
    assert_in_out_err(["-we", "1.times do\n  a=1\nend"], "", [], [], feature3446)
    assert_in_out_err(["-we", "def foo\n  1.times do\n    a=1\n  end\nend"], "", [], ["-e:3: warning: assigned but unused variable - a"], feature3446)
    assert_in_out_err(["-we", "def foo\n""  1.times do |a| end\n""end"], "", [], [])
    feature6693 = '[ruby-core:46160]'
    assert_in_out_err(["-we", "def foo\n  _a=1\nend"], "", [], [], feature6693)
    bug7408 = '[ruby-core:49659]'
    assert_in_out_err(["-we", "def foo\n  a=1\n :a\nend"], "", [], ["-e:2: warning: assigned but unused variable - a"], bug7408)
    feature7730 = '[ruby-core:51580]'
    assert_in_out_err(["-w", "-"], "a=1", [], ["-:1: warning: assigned but unused variable - a"], feature7730)
    assert_in_out_err(["-w", "-"], "eval('a=1')", [], [], feature7730)
  end

  def test_script_from_stdin
    begin
      require 'pty'
      require 'io/console'
    rescue LoadError
      return
    end
    require 'timeout'
    result = nil
    IO.pipe {|r, w|
      begin
        PTY.open {|m, s|
          s.echo = false
          m.print("\C-d")
          pid = spawn(EnvUtil.rubybin, :in => s, :out => w)
          w.close
          assert_nothing_raised('[ruby-dev:37798]') do
            result = EnvUtil.timeout(3) {r.read}
          end
          Process.wait pid
        }
      rescue RuntimeError
        omit $!
      end
    }
    assert_equal("", result, '[ruby-dev:37798]')
    IO.pipe {|r, w|
      PTY.open {|m, s|
	s.echo = false
	pid = spawn(EnvUtil.rubybin, :in => s, :out => w)
	w.close
	m.print("$stdin.read; p $stdin.gets\n\C-d")
	m.print("abc\n\C-d")
	m.print("zzz\n")
	result = r.read
	Process.wait pid
      }
    }
    assert_equal("\"zzz\\n\"\n", result, '[ruby-core:30910]')
  end

  def test_unmatching_glob
    bug3851 = '[ruby-core:32478]'
    a = "a[foo"
    Dir.mktmpdir do |dir|
      open(File.join(dir, a), "w") {|f| f.puts("p 42")}
      assert_in_out_err(["-C", dir, a], "", ["42"], [], bug3851)
      File.unlink(File.join(dir, a))
      assert_in_out_err(["-C", dir, a], "", [], /LoadError/, bug3851)
    end
  end

  case RUBY_PLATFORM
  when /mswin|mingw/
    def test_command_line_glob_nonascii
      bug10555 = '[ruby-dev:48752] [Bug #10555]'
      name = "\u{3042}.txt"
      expected = name.encode("external") rescue "?.txt"
      with_tmpchdir do |dir|
        open(name, "w") {}
        assert_in_out_err(["-e", "puts ARGV", "?.txt"], "", [expected], [],
                          bug10555, encoding: "external")
      end
    end

    def test_command_line_progname_nonascii
      omit "not working on MinGW" if /mingw/ =~ RUBY_PLATFORM
      bug10555 = '[ruby-dev:48752] [Bug #10555]'
      name = expected = nil
      unless (0x80..0x10000).any? {|c|
               name = c.chr(Encoding::UTF_8)
               expected = name.encode("locale") rescue nil
             }
        omit "can't make locale name"
      end
      name << ".rb"
      expected << ".rb"
      with_tmpchdir do |dir|
        open(name, "w") {|f| f.puts "puts File.basename($0)"}
        assert_in_out_err([name], "", [expected], [],
                          bug10555, encoding: "locale")
      end
    end

    def test_command_line_glob_with_dir
      bug10941 = '[ruby-core:68430] [Bug #10941]'
      with_tmpchdir do |dir|
        Dir.mkdir('test')
        assert_in_out_err(["-e", "", "test/*"], "", [], [], bug10941)
      end
    end

    Ougai = %W[\u{68ee}O\u{5916}.txt \u{68ee 9d0e 5916}.txt \u{68ee 9dd7 5916}.txt]
    def test_command_line_glob_noncodepage
      with_tmpchdir do |dir|
        Ougai.each {|f| open(f, "w") {}}
        assert_in_out_err(["-Eutf-8", "-e", "puts ARGV", "*"], "", Ougai, encoding: "utf-8")
        ougai = Ougai.map {|f| f.encode("external", replace: "?")}
        assert_in_out_err(["-e", "puts ARGV", "*.txt"], "", ougai)
      end
    end

    def assert_e_script_encoding(str, args = [])
      cmds = [
        EnvUtil::LANG_ENVS.inject({}) {|h, k| h[k] = ENV[k]; h},
        *args,
        '-e', "s = '#{str}'",
        '-e', 'puts s.encoding.name',
        '-e', 'puts s.dump',
      ]
      assert_in_out_err(cmds, "", [str.encoding.name, str.dump], [],
                        "#{str.encoding}:#{str.dump} #{args.inspect}")
    end

    # tested codepages: 437 850 852 855 932 65001
    # Since the codepage is shared all processes per conhost.exe, do
    # not chcp, or parallel test may break.
    def test_locale_codepage
      omit "not working on MinGW" if /mingw/ =~ RUBY_PLATFORM
      locale = Encoding.find("locale")
      list = %W"\u{c7} \u{452} \u{3066 3059 3068}"
      list.each do |s|
        assert_e_script_encoding(s, %w[-U])
      end
      list.each do |s|
        s = s.encode(locale) rescue next
        assert_e_script_encoding(s)
        assert_e_script_encoding(s, %W[-E#{locale.name}])
      end
    end
  when /cygwin/
    def test_command_line_non_ascii
      assert_separately([{"LC_ALL"=>"ja_JP.SJIS"}, "-", "\u{3042}".encode("SJIS")], <<-"end;")
        bug12184 = '[ruby-dev:49519] [Bug #12184]'
        a = ARGV[0]
        assert_equal([Encoding::SJIS, 130, 160], [a.encoding, *a.bytes], bug12184)
      end;
    end
  end

  def test_script_is_directory
    feature2408 = '[ruby-core:26925]'
    assert_in_out_err(%w[.], "", [], /Is a directory -- \./, feature2408)
  end

  def test_pflag_gsub
    bug7157 = '[ruby-core:47967]'
    assert_in_out_err(['-p', '-e', 'gsub(/t.*/){"TEST"}'], %[test], %w[TEST], [], bug7157)
  end

  def test_pflag_sub
    bug7157 = '[ruby-core:47967]'
    assert_in_out_err(['-p', '-e', 'sub(/t.*/){"TEST"}'], %[test], %w[TEST], [], bug7157)
  end

  def assert_norun_with_rflag(*opt)
    bug10435 = "[ruby-dev:48712] [Bug #10435]: should not run with #{opt} option"
    stderr = []
    Tempfile.create(%w"bug10435- .rb") do |script|
      dir, base = File.split(script.path)
      File.write(script, "abort ':run'\n")
      opts = ['-C', dir, '-r', "./#{base}", *opt]
      _, e = assert_in_out_err([*opts, '-ep'], "", //)
      stderr.concat(e) if e
      stderr << "---"
      _, e = assert_in_out_err([*opts, base], "", //)
      stderr.concat(e) if e
    end
    assert_not_include(stderr, ":run", bug10435)
  end

  def test_dump_syntax_with_rflag
    assert_norun_with_rflag('-c')
    assert_norun_with_rflag('--dump=syntax')
  end

  def test_dump_yydebug_with_rflag
    assert_norun_with_rflag('-y')
    assert_norun_with_rflag('--dump=yydebug')
  end

  def test_dump_parsetree_with_rflag
    assert_norun_with_rflag('--dump=parsetree')
    assert_norun_with_rflag('--dump=parsetree', '-e', '#frozen-string-literal: true')
    assert_norun_with_rflag('--dump=parsetree+error_tolerant')
    assert_norun_with_rflag('--dump=parse+error_tolerant')
    assert_in_out_err(%w(--parser=prism --dump=parsetree -e ""), "", /ProgramNode/, PRISM_WARNING, encoding: "UTF-8")
  end

  def test_dump_insns_with_rflag
    assert_norun_with_rflag('--dump=insns')
  end

  def test_frozen_string_literal
    all_assertions do |a|
      [["disable", "false"], ["enable", "true"]].each do |opt, exp|
        %W[frozen_string_literal frozen-string-literal].each do |arg|
          key = "#{opt}=#{arg}"
          negopt = exp == "true" ? "disable" : "enable"
          env = {"RUBYOPT"=>"--#{negopt}=#{arg}"}
          a.for(key) do
            assert_in_out_err([env, "--disable=gems", "--#{key}"], 'p("foo".frozen?)', [exp])
          end
        end
      end
      %W"disable enable".product(%W[false true]) do |opt, exp|
        a.for("#{opt}=>#{exp}") do
          assert_in_out_err(["-w", "--disable=gems", "--#{opt}=frozen-string-literal"], <<-"end;", [exp])
            #-*- frozen-string-literal: #{exp} -*-
            p("foo".frozen?)
          end;
        end
      end
    end
  end

  def test_frozen_string_literal_debug
    with_debug_pat = /created at/
    wo_debug_pat = /can\'t modify frozen String: "\w+" \(FrozenError\)\n\z/
    frozen = [
      ["--enable-frozen-string-literal", true],
      ["--disable-frozen-string-literal", false],
      [nil, false],
    ]
    debugs = [
      ["--debug-frozen-string-literal", true],
      ["--debug=frozen-string-literal", true],
      ["--debug", true],
      [nil, false],
    ]
    opts = ["--disable=gems"]
    frozen.product(debugs) do |(opt1, freeze), (opt2, debug)|
      opt = opts + [opt1, opt2].compact
      err = !freeze ? [] : debug ? with_debug_pat : wo_debug_pat
      [
        ['"foo" << "bar"', err],
        ['"foo#{123}bar" << "bar"', []],
        ['+"foo#{123}bar" << "bar"', []],
        ['-"foo#{123}bar" << "bar"', wo_debug_pat],
      ].each do |code, expected|
        assert_in_out_err(opt, code, [], expected, "#{opt} #{code}")
      end
    end
  end

  def test___dir__encoding
    lang = {"LC_ALL"=>ENV["LC_ALL"]||ENV["LANG"]}
    with_tmpchdir do
      testdir = "\u30c6\u30b9\u30c8"
      Dir.mkdir(testdir)
      Dir.chdir(testdir) do
        open("test.rb", "w") do |f|
          f.puts <<-END
            if __FILE__.encoding == __dir__.encoding
              p true
            else
              puts "__FILE__: \#{__FILE__.encoding}, __dir__: \#{__dir__.encoding}"
            end
          END
        end
        r, = EnvUtil.invoke_ruby([lang, "test.rb"], "", true)
        assert_equal "true", r.chomp, "the encoding of __FILE__ and __dir__ should be same"
      end
    end
  end

  def test_cwd_encoding
    with_tmpchdir do
      testdir = "\u30c6\u30b9\u30c8"
      Dir.mkdir(testdir)
      Dir.chdir(testdir) do
        File.write("a.rb", "require './b'")
        File.write("b.rb", "puts 'ok'")
        assert_ruby_status([{"RUBYLIB"=>"."}, *%w[-E cp932:utf-8 a.rb]])
      end
    end
  end

  def test_rubylib_invalid_encoding
    env = {"RUBYLIB"=>"\xFF", "LOCALE"=>"en_US.UTF-8", "LC_ALL"=>"en_US.UTF-8"}
    assert_ruby_status([env, "-e;"])
  end

  def test_null_script
    omit "#{IO::NULL} is not a character device" unless File.chardev?(IO::NULL)
    assert_in_out_err([IO::NULL], success: true)
  end

  def test_free_at_exit_env_var
    env = {"RUBY_FREE_AT_EXIT"=>"1"}
    assert_ruby_status([env, "-e;"])
    assert_in_out_err([env, "-W"], "", [], /Free at exit is experimental and may be unstable/)
  end
end
