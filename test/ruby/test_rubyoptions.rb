# -*- coding: us-ascii -*-
require 'test/unit'

require 'tmpdir'
require 'tempfile'

class TestRubyOptions < Test::Unit::TestCase
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
      assert_operator(r.size, :<=, 24)
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
                      "foo\nbar\nbaz\n") do |r, e|
      assert_equal(
        [ '[true, true, true]', 'foo',
          '[true, true, true]', 'bar',
          '[true, true, true]', 'baz' ], r)
      assert_equal([], e)
    end
  end

  def test_warning
    save_rubyopt = ENV['RUBYOPT']
    ENV['RUBYOPT'] = nil
    assert_in_out_err(%w(-W0 -e) + ['p $-W'], "", %w(0), [])
    assert_in_out_err(%w(-W1 -e) + ['p $-W'], "", %w(1), [])
    assert_in_out_err(%w(-Wx -e) + ['p $-W'], "", %w(1), [])
    assert_in_out_err(%w(-W -e) + ['p $-W'], "", %w(2), [])
  ensure
    ENV['RUBYOPT'] = save_rubyopt
  end

  def test_safe_level
    assert_in_out_err(%w(-T -e) + [""], "", [],
                      /no -e allowed in tainted mode \(SecurityError\)/)

    assert_in_out_err(%w(-T4 -S foo.rb), "", [],
                      /no -S allowed in tainted mode \(SecurityError\)/)
  end

  def test_debug
    assert_in_out_err(["--disable-gems", "-de", "p $DEBUG"], "", %w(true), [])

    assert_in_out_err(["--disable-gems", "--debug", "-e", "p $DEBUG"],
                      "", %w(true), [])
  end

  def test_verbose
    assert_in_out_err(["-vve", ""]) do |r, e|
      assert_match(/^ruby #{RUBY_VERSION}(?:[p ]|dev|rc).*? \[#{RUBY_PLATFORM}\]$/, r.join)
      assert_equal RUBY_DESCRIPTION, r.join.chomp
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
    assert_in_out_err(%w(--enable all -e) + [""], "", [], [])
    assert_in_out_err(%w(--enable-all -e) + [""], "", [], [])
    assert_in_out_err(%w(--enable=all -e) + [""], "", [], [])
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
  end

  def test_kanji
    assert_in_out_err(%w(-KU), "p '\u3042'") do |r, e|
      assert_equal("\"\u3042\"", r.join.force_encoding(Encoding::UTF_8))
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
    assert_in_out_err(%w(--version)) do |r, e|
      assert_match(/^ruby #{RUBY_VERSION}(?:[p ]|dev|rc).*? \[#{RUBY_PLATFORM}\]$/, r.join)
      assert_equal RUBY_DESCRIPTION, r.join.chomp
      assert_equal([], e)
    end
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
  end

  def test_autosplit
    assert_in_out_err(%w(-an -F: -e) + ["p $F"], "foo:bar:baz\nqux:quux:quuux\n",
                      ['["foo", "bar", "baz\n"]', '["qux", "quux", "quuux\n"]'], [])
  end

  def test_chdir
    assert_in_out_err(%w(-C), "", [], /Can't chdir/)

    assert_in_out_err(%w(-C test_ruby_test_rubyoptions_foobarbazqux), "", [], /Can't chdir/)

    d = Dir.tmpdir
    assert_in_out_err(["-C", d, "-e", "puts Dir.pwd"]) do |r, e|
      assert_file.identical?(r.join, d)
      assert_equal([], e)
    end
  end

  def test_yydebug
    assert_in_out_err(["-ye", ""]) do |r, e|
      assert_equal([], r)
      assert_not_equal([], e)
    end

    assert_in_out_err(%w(--yydebug -e) + [""]) do |r, e|
      assert_equal([], r)
      assert_not_equal([], e)
    end
  end

  def test_encoding
    assert_in_out_err(%w(--encoding), "", [], /missing argument for --encoding/)

    assert_in_out_err(%w(--encoding test_ruby_test_rubyoptions_foobarbazqux), "", [],
                      /unknown encoding name - test_ruby_test_rubyoptions_foobarbazqux \(RuntimeError\)/)

    if /mswin|mingw|aix/ =~ RUBY_PLATFORM &&
      (str = "\u3042".force_encoding(Encoding.find("locale"))).valid_encoding?
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
    assert_in_out_err(%w(-c -e a=1+1 -e !a), "", ["Syntax OK"], [])
  end

  def test_invalid_option
    assert_in_out_err(%w(--foobarbazqux), "", [], /invalid option --foobarbazqux/)

    assert_in_out_err(%W(-\r -e) + [""], "", [], [])

    assert_in_out_err(%W(-\rx), "", [], /invalid option -\\x0D  \(-h will show valid options\) \(RuntimeError\)/)

    assert_in_out_err(%W(-\x01), "", [], /invalid option -\\x01  \(-h will show valid options\) \(RuntimeError\)/)

    assert_in_out_err(%w(-Z), "", [], /invalid option -Z  \(-h will show valid options\) \(RuntimeError\)/)
  end

  def test_rubyopt
    rubyopt_orig = ENV['RUBYOPT']

    ENV['RUBYOPT'] = ' - -'
    assert_in_out_err([], "", [], [])

    ENV['RUBYOPT'] = '-e "p 1"'
    assert_in_out_err([], "", [], /invalid switch in RUBYOPT: -e \(RuntimeError\)/)

    ENV['RUBYOPT'] = '-T1'
    assert_in_out_err(["--disable-gems"], "", [], /no program input from stdin allowed in tainted mode \(SecurityError\)/)

    ENV['RUBYOPT'] = '-T4'
    assert_in_out_err(["--disable-gems"], "", [], /no program input from stdin allowed in tainted mode \(SecurityError\)/)

    ENV['RUBYOPT'] = '-Eus-ascii -KN'
    assert_in_out_err(%w(-Eutf-8 -KU), "p '\u3042'") do |r, e|
      assert_equal("\"\u3042\"", r.join.force_encoding(Encoding::UTF_8))
      assert_equal([], e)
    end

  ensure
    if rubyopt_orig
      ENV['RUBYOPT'] = rubyopt_orig
    else
      ENV.delete('RUBYOPT')
    end
  end

  def test_search
    rubypath_orig = ENV['RUBYPATH']
    path_orig = ENV['PATH']

    Tempfile.create(["test_ruby_test_rubyoption", ".rb"]) {|t|
      t.puts "p 1"
      t.close

      @verbose = $VERBOSE
      $VERBOSE = nil

      ENV['PATH'] = File.dirname(t.path)

      assert_in_out_err(%w(-S) + [File.basename(t.path)], "", %w(1), [])

      ENV['RUBYPATH'] = File.dirname(t.path)

      assert_in_out_err(%w(-S) + [File.basename(t.path)], "", %w(1), [])
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

    assert_in_out_err([{'RUBYOPT' => nil}], "#!ruby -KU -Eutf-8\r\np \"\u3042\"\r\n") do |r, e|
      assert_equal("\"\u3042\"", r.join.force_encoding(Encoding::UTF_8))
      assert_equal([], e)
    end

    bug4118 = '[ruby-dev:42680]'
    assert_in_out_err(%w[], "#!/bin/sh\n""#!shebang\n""#!ruby\n""puts __LINE__\n",
                      %w[4], [], bug4118)
    assert_in_out_err(%w[-x], "#!/bin/sh\n""#!shebang\n""#!ruby\n""puts __LINE__\n",
                      %w[4], [], bug4118)
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
      warning = ' warning: found = in conditional, should be =='
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
    Tempfile.create(["test_ruby_test_rubyoption", ".rb"]) {|t|
      t.puts "begin"
      t.puts " end"
      t.flush
      err = ["#{t.path}:2: warning: mismatched indentations at 'end' with 'begin' at 1"]
      assert_in_out_err(["-w", t.path], "", [], err)
      assert_in_out_err(["-wr", t.path, "-e", ""], "", [], err)

      t.rewind
      t.puts "# -*- warn-indent: false -*-"
      t.puts "begin"
      t.puts " end"
      t.flush
      assert_in_out_err(["-w", t.path], "", [], [], '[ruby-core:25442]')

      err = ["#{t.path}:4: warning: mismatched indentations at 'end' with 'begin' at 3"]
      t.rewind
      t.puts "# -*- warn-indent: false -*-"
      t.puts "# -*- warn-indent: true -*-"
      t.puts "begin"
      t.puts " end"
      t.flush
      assert_in_out_err(["-w", t.path], "", [], err, '[ruby-core:25442]')

      err = ["#{t.path}:4: warning: mismatched indentations at 'end' with 'begin' at 2"]
      t.rewind
      t.puts "# -*- warn-indent: true -*-"
      t.puts "begin"
      t.puts "# -*- warn-indent: false -*-"
      t.puts " end"
      t.flush
      assert_in_out_err(["-w", t.path], "", [], [], '[ruby-core:25442]')
    }
  end

  def test_notfound
    notexist = "./notexist.rb"
    rubybin = EnvUtil.rubybin.dup
    rubybin.gsub!(%r(/), '\\') if /mswin|mingw/ =~ RUBY_PLATFORM
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
        File.symlink(n1, n2)
        IO.popen([ruby, n2]) {|f|
          assert_equal(n2, f.read)
        }
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
    PSCMD.pop if PSCMD
  end

  def test_set_program_name
    skip "platform dependent feature" unless defined?(PSCMD) and PSCMD

    with_tmpchdir do
      write_file("test-script", "$0 = 'hello world'; /test-script/ =~ Process.argv0 or $0 = 'Process.argv0 changed!'; sleep 60")

      pid = spawn(EnvUtil.rubybin, "test-script")
      ps = nil
      10.times do
        sleep 0.1
        ps = `#{PSCMD.join(' ')} #{pid}`
        break if /hello world/ =~ ps
      end
      assert_match(/hello world/, ps)
      Process.kill :KILL, pid
      Process.wait(pid)
    end
  end

  def test_setproctitle
    skip "platform dependent feature" unless defined?(PSCMD) and PSCMD

    with_tmpchdir do
      write_file("test-script", "$_0 = $0.dup; Process.setproctitle('hello world'); $0 == $_0 or Process.setproctitle('$0 changed!'); sleep 60")

      pid = spawn(EnvUtil.rubybin, "test-script")
      ps = nil
      10.times do
        sleep 0.1
        ps = `#{PSCMD.join(' ')} #{pid}`
        break if /hello world/ =~ ps
      end
      assert_match(/hello world/, ps)
      Process.kill :KILL, pid
      Process.wait(pid)
    end
  end

  module SEGVTest
    opts = {}
    if /mswin|mingw/ =~ RUBY_PLATFORM
      additional = /[\s\w\.\']*/
    else
      opts[:rlimit_core] = 0
      additional = nil
    end
    ExecOptions = opts.freeze

    ExpectedStderrList = [
      %r(
        -e:(?:1:)?\s\[BUG\]\sSegmentation\sfault.*\n
      )x,
      %r(
        #{ Regexp.quote(RUBY_DESCRIPTION) }\n\n
      )x,
      %r(
        (?:--\s(?:.+\n)*\n)?
        --\sControl\sframe\sinformation\s-+\n
        (?:c:.*\n)*
      )x,
      %r(
        (?:
        --\sRuby\slevel\sbacktrace\sinformation\s----------------------------------------\n
        -e:1:in\s\`<main>\'\n
        -e:1:in\s\`kill\'\n
        )?
      )x,
      %r(
        (?:
          --\sC\slevel\sbacktrace\sinformation\s-------------------------------------------\n
          (?:(?:.*\s)?\[0x\h+\]\n)*\n
        )?
      )x,
      :*,
      %r(
        \[NOTE\]\n
        You\smay\shave\sencountered\sa\sbug\sin\sthe\sRuby\sinterpreter\sor\sextension\slibraries.\n
        Bug\sreports\sare\swelcome.\n
        (?:.*\n)?
        For\sdetails:\shttp:\/\/.*\.ruby-lang\.org/.*\n
        \n
      )x,
    ]
    ExpectedStderrList << additional if additional
  end

  def assert_segv(args, message=nil)
    test_stdin = ""
    opt = SEGVTest::ExecOptions.dup

    _, stderr, status = EnvUtil.invoke_ruby(args, test_stdin, false, true, **opt)
    stderr.force_encoding("ASCII-8BIT")

    if signo = status.termsig
      sleep 0.1
      EnvUtil.diagnostic_reports(Signal.signame(signo), EnvUtil.rubybin, status.pid, Time.now)
    end

    assert_pattern_list(SEGVTest::ExpectedStderrList, stderr, message)

    status
  end

  def test_segv_test
    assert_segv(["--disable-gems", "-e", "Process.kill :SEGV, $$"])
  end

  def test_segv_loaded_features
    opts = SEGVTest::ExecOptions.dup

    bug7402 = '[ruby-core:49573]'

    status = Dir.mktmpdir("segv_test") do |tmpdir|
      assert_in_out_err(['-e', 'class Bogus; def to_str; exit true; end; end',
                         '-e', '$".clear',
                         '-e', '$".unshift Bogus.new',
                         '-e', '(p $"; abort) unless $".size == 1',
                         '-e', 'Process.kill :SEGV, $$',
                         '-C', tmpdir,
                        ],
                        "", [], //,
                        nil,
                        opts)
    end
    if signo = status.termsig
      sleep 0.1
      EnvUtil.diagnostic_reports(Signal.signame(signo), EnvUtil.rubybin, status.pid, Time.now)
    end
    assert_not_predicate(status, :success?, "segv but success #{bug7402}")
  end

  def test_segv_setproctitle
    bug7597 = '[ruby-dev:46786]'
    Tempfile.create(["test_ruby_test_bug7597", ".rb"]) {|t|
      t.write "f" * 100
      t.flush
      assert_segv(["--disable-gems", "-e", "$0=ARGV[0]; Process.kill :SEGV, $$", t.path], bug7597)
    }
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

  def test_shadowing_variable
    bug4130 = '[ruby-dev:42718]'
    assert_in_out_err(["-we", "def foo\n""  a=1\n""  1.times do |a| end\n""  a\n""end"],
                      "", [], ["-e:3: warning: shadowing outer local variable - a"], bug4130)
    assert_in_out_err(["-we", "def foo\n""  a=1\n""  1.times do |a| end\n""end"],
                      "", [],
                      ["-e:3: warning: shadowing outer local variable - a",
                       "-e:2: warning: assigned but unused variable - a",
                      ], bug4130)
    feature6693 = '[ruby-core:46160]'
    assert_in_out_err(["-we", "def foo\n""  _a=1\n""  1.times do |_a| end\n""end"],
                      "", [], [], feature6693)
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
            result = Timeout.timeout(3) {r.read}
          end
          Process.wait pid
        }
      rescue RuntimeError
        skip $!
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

  if /mswin|mingw/ =~ RUBY_PLATFORM
    def test_command_line_glob_nonascii
      bug10555 = '[ruby-dev:48752] [Bug #10555]'
      name = "\u{3042}.txt"
      expected = name.encode("locale") rescue "?.txt"
      with_tmpchdir do |dir|
        open(name, "w") {}
        assert_in_out_err(["-e", "puts ARGV", "?.txt"], "", [expected], [],
                          bug10555, encoding: "locale")
      end
    end

    def test_command_line_progname_nonascii
      bug10555 = '[ruby-dev:48752] [Bug #10555]'
      name = "\u{3042}.rb"
      expected = name.encode("locale") rescue "?.rb"
      with_tmpchdir do |dir|
        open(name, "w") {|f| f.puts "puts File.basename($0)"}
        assert_in_out_err([name], "", [expected], [],
                          bug10555, encoding: "locale")
      end
    end
  end

  if /mswin|mingw/ =~ RUBY_PLATFORM
    Ougai = %W[\u{68ee}O\u{5916}.txt \u{68ee 9d0e 5916}.txt \u{68ee 9dd7 5916}.txt]
    def test_command_line_glob_noncodepage
      with_tmpchdir do |dir|
        Ougai.each {|f| open(f, "w") {}}
        assert_in_out_err(["-Eutf-8", "-e", "puts ARGV", "*"], "", Ougai, encoding: "utf-8")
        ougai = Ougai.map {|f| f.encode("locale", replace: "?")}
        assert_in_out_err(["-e", "puts ARGV", "*.txt"], "", ougai)
      end
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

  def assert_norun_with_rflag(opt)
    bug10435 = "[ruby-dev:48712] [Bug #10435]: should not run with #{opt} option"
    stderr = []
    Tempfile.create(%w"bug10435- .rb") do |script|
      dir, base = File.split(script.path)
      script.puts "abort ':run'"
      script.close
      opts = ['-C', dir, '-r', "./#{base}", opt]
      assert_in_out_err([*opts, '-ep']) do |_, e|
        stderr.concat(e)
      end
      stderr << "---"
      assert_in_out_err([*opts, base]) do |_, e|
        stderr.concat(e)
      end
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
  end

  def test_dump_insns_with_rflag
    assert_norun_with_rflag('--dump=insns')
  end
end
