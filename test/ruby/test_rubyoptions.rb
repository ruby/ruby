require 'test/unit'

unless /(mswin|bccwin|mingw|emx)/ =~ RUBY_PLATFORM

require 'timeout'
require 'tmpdir'
require 'tempfile'
require 'open3'
require_relative 'envutil'

class TestRubyOptions < Test::Unit::TestCase
  def ruby(*args)
    ruby = EnvUtil.rubybin
    stdin, stdout, stderr = Open3.popen3(*([ruby] + args))
    Timeout.timeout(10) do
      yield(stdin, stdout, stderr)
    end
  ensure
    stdin .close unless !stdin  || stdin .closed?
    stdout.close unless !stdout || stdout.closed?
    stderr.close unless !stderr || stderr.closed?
  end

  def test_source_file
    ruby('') do |w, r, e|
      w.close
      assert_equal('', e.read)
      assert_equal('', r.read)
    end
  end

  def test_usage
    ruby('-h') do |w, r, e|
      w.close
      assert(r.readlines.size <= 24)
    end

    ruby('--help') do |w, r, e|
      w.close
      assert(r.readlines.size <= 24)
    end
  end

  def test_option_variables
    ruby('-e', 'p [$-p, $-l, $-a]') do |w, r, e|
      assert_equal('[false, false, false]', r.read.chomp)
    end

    ruby('-p', '-l', '-a', '-e', 'p [$-p, $-l, $-a]') do |w, r, e|
      w.puts 'foo'
      w.puts 'bar'
      w.puts 'baz'
      w.close_write
      r = r.readlines.map {|l| l.chomp }
      assert_equal(
        [ '[true, true, true]', 'foo',
          '[true, true, true]', 'bar',
          '[true, true, true]', 'baz' ], r)
    end
  end

  def test_warning
    ruby('-W0', '-e', 'p $-W') do |w, r, e|
      assert_equal('0', r.read.chomp)
    end
    ruby('-W1', '-e', 'p $-W') do |w, r, e|
      assert_equal('1', r.read.chomp)
    end
    ruby('-Wx', '-e', 'p $-W') do |w, r, e|
      assert_equal('1', r.read.chomp)
    end
    ruby('-W', '-e', 'p $-W') do |w, r, e|
      assert_equal('2', r.read.chomp)
    end
  end

  def test_safe_level
    ruby('-T', '-e', '') do |w, r, e|
      assert(e.read.chomp =~ /no -e allowed in tainted mode \(SecurityError\)/)
    end

    ruby('-T4', '-S', 'foo.rb') do |w, r, e|
      assert(e.read.chomp =~ /no -S allowed in tainted mode \(SecurityError\)/)
    end
  end

  def test_debug
    ruby('-de', 'p $DEBUG') do |w, r, e|
      assert_equal('true', r.read.chomp)
    end

    ruby('--debug', '-e', 'p $DEBUG') do |w, r, e|
      assert_equal('true', r.read.chomp)
    end
  end

  def test_verbose
    ruby('-vve', '') do |w, r, e|
      assert(r.read.chomp =~ /^ruby #{RUBY_VERSION} .*? \[#{RUBY_PLATFORM}\]$/)
    end

    ruby('--verbose', '-e', 'p $VERBOSE') do |w, r, e|
      assert_equal('true', r.read.chomp)
    end

    ruby('--verbose') do |w, r, e|
      assert_equal('', e.read)
      assert_equal('', r.read)
    end
  end

  def test_copyright
    ruby('--copyright') do |w, r, e|
      assert(r.read.chomp =~ /^ruby - Copyright \(C\) 1993-\d+ Yukihiro Matsumoto$/)
    end

    ruby('--verbose', '-e', 'p $VERBOSE') do |w, r, e|
      assert_equal('true', r.read.chomp)
    end
  end

  def test_enable
    ruby('--enable', 'all', '-e', '') do |w, r, e|
      assert_equal('', e.read)
      assert_equal('', r.read)
    end

    ruby('--enable-all', '-e', '') do |w, r, e|
      assert_equal('', e.read)
      assert_equal('', r.read)
    end

    ruby('--enable=all', '-e', '') do |w, r, e|
      assert_equal('', e.read)
      assert_equal('', r.read)
    end

    ruby('--enable', 'foobarbazqux', '-e', '') do |w, r, e|
      assert(e.read.chomp =~ /unknown argument for --enable: `foobarbazqux'/)
    end

    ruby('--enable') do |w, r, e|
      assert(e.read.chomp =~ /missing argument for --enable/)
    end
  end

  def test_disable
    ruby('--disable', 'all', '-e', '') do |w, r, e|
      assert_equal('', e.read)
      assert_equal('', r.read)
    end

    ruby('--disable-all', '-e', '') do |w, r, e|
      assert_equal('', e.read)
      assert_equal('', r.read)
    end

    ruby('--disable=all', '-e', '') do |w, r, e|
      assert_equal('', e.read)
      assert_equal('', r.read)
    end

    ruby('--disable', 'foobarbazqux', '-e', '') do |w, r, e|
      assert(e.read.chomp =~ /unknown argument for --disable: `foobarbazqux'/)
    end

    ruby('--disable') do |w, r, e|
      assert(e.read.chomp =~ /missing argument for --disable/)
    end
  end

  def test_kanji
    ruby('-KU') do |w, r, e|
      w.puts "p '\u3042'"
      w.close
      assert_equal("\"\u3042\"", r.read.chomp.force_encoding(Encoding.find('utf-8')))
    end

    ruby('-KE', '-e', '') do |w, r, e|
      assert_equal("", r.read)
      assert_equal("", e.read)
    end

    ruby('-KS', '-e', '') do |w, r, e|
      assert_equal("", r.read)
      assert_equal("", e.read)
    end

    ruby('-KN', '-e', '') do |w, r, e|
      assert_equal("", r.read)
      assert_equal("", e.read)
    end
  end

  def test_version
    ruby('--version') do |w, r, e|
      assert(r.read.chomp =~ /^ruby #{RUBY_VERSION} .*? \[#{RUBY_PLATFORM}\]$/)
    end
  end

  def test_eval
    ruby('-e') do |w, r, e|
      assert(e.read.chomp =~ /no code specified for -e \(RuntimeError\)/)
    end
  end

  def test_require
    ruby('-r', 'pp', '-e', 'pp 1') do |w, r, e|
      assert_equal('1', r.read.chomp)
    end
    ruby('-rpp', '-e', 'pp 1') do |w, r, e|
      w.close
      assert_equal('1', r.read.chomp)
    end
  end

  def test_include
    d = Dir.tmpdir
    ruby('-I' + d, '-e', '') do |w, r, e|
      assert_equal('', e.read.chomp)
      assert_equal('', r.read.chomp)
    end

    d = Dir.tmpdir
    ruby('-I', d, '-e', '') do |w, r, e|
      assert_equal('', e.read.chomp)
      assert_equal('', r.read.chomp)
    end
  end

  def test_separator
    ruby('-000', '-e', 'print gets') do |w, r, e|
      w.write "foo\nbar\0baz"
      w.close
      assert_equal('', e.read)
      assert_equal("foo\nbar\0baz", r.read)
    end

    ruby('-0141', '-e', 'print gets') do |w, r, e|
      w.write "foo\nbar\0baz"
      w.close
      assert_equal('', e.read)
      assert_equal("foo\nba", r.read)
    end

    ruby('-0e', 'print gets') do |w, r, e|
      w.write "foo\nbar\0baz"
      w.close
      assert_equal('', e.read)
      assert_equal("foo\nbar\0", r.read)
    end
  end

  def test_autosplit
    ruby('-an', '-F:', '-e', 'p $F') do |w, r, e|
      w.puts "foo:bar:baz"
      w.puts "qux:quux:quuux"
      w.close
      r = r.readlines.map {|l| l.chomp }
      assert_equal(['["foo", "bar", "baz\n"]', '["qux", "quux", "quuux\n"]'], r)
    end
  end

  def test_chdir
    ruby('-C') do |w, r, e|
      assert(e.read.chomp =~ /Can't chdir/)
    end

    ruby('-C', 'test_ruby_test_rubyoptions_foobarbazqux') do |w, r, e|
      assert(e.read.chomp =~ /Can't chdir/)
    end

    d = Dir.tmpdir
    ruby('-C', d, '-e', 'puts Dir.pwd') do |w, r, e|
      assert_equal('', e.read)
      assert(File.identical?(r.read.chomp, d))
    end
  end

  def test_yydebug
    ruby('-ye', '') do |w, r, e|
      assert_equal("", r.read)
      assert_nothing_raised { e.read }
    end

    ruby('--yydebug', '-e', '') do |w, r, e|
      assert_equal("", r.read)
      assert_nothing_raised { e.read }
    end
  end

  def test_encoding
    ruby('-Eutf-8') do |w, r, e|
      w.puts "p '\u3042'"
      w.close
      assert_equal("\"\u3042\"", r.read.chomp.force_encoding(Encoding.find('utf-8')))
    end

    ruby('--encoding') do |w, r, e|
      assert(e.read.chomp =~ /missing argument for --encoding/)
    end

    ruby('--encoding', 'test_ruby_test_rubyoptions_foobarbazqux') do |w, r, e|
      assert(e.read.chomp =~ /unknown encoding name - test_ruby_test_rubyoptions_foobarbazqux \(RuntimeError\)/)
    end

    ruby('--encoding', 'utf-8') do |w, r, e|
      w.puts "p '\u3042'"
      w.close
      assert_equal("\"\u3042\"", r.read.chomp.force_encoding(Encoding.find('utf-8')))
    end
  end

  def test_syntax_check
    ruby('-c', '-e', '1+1') do |w, r, e|
      assert_equal('Syntax OK', r.read.chomp)
    end
  end

  def test_invalid_option
    ruby('--foobarbazqux') do |w, r, e|
      assert(e.read.chomp =~ /invalid option --foobarbazqux/)
    end

    ruby("-\r", '-e', '') do |w, r, e|
      assert_equal('', e.read)
      assert_equal('', r.read)
    end

    ruby("-\rx") do |w, r, e|
      assert(e.read.chomp =~ /invalid option -\\x0D  \(-h will show valid options\) \(RuntimeError\)/)
    end

    ruby("-\x01") do |w, r, e|
      assert(e.read.chomp =~ /invalid option -\\x01  \(-h will show valid options\) \(RuntimeError\)/)
    end

    ruby('-Z') do |w, r, e|
      assert(e.read.chomp =~ /invalid option -Z  \(-h will show valid options\) \(RuntimeError\)/)
    end
  end

  def test_rubyopt
    rubyopt_orig = ENV['RUBYOPT']

    ENV['RUBYOPT'] = ' - -'
    ruby do |w, r, e|
      w.close
      assert_equal('', e.read)
      assert_equal('', r.read)
    end

    ENV['RUBYOPT'] = '-e "p 1"'
    ruby do |w, r, e|
      assert(e.read.chomp =~ /invalid switch in RUBYOPT: -e \(RuntimeError\)/)
    end

    ENV['RUBYOPT'] = '-T1'
    ruby do |w, r, e|
      assert(e.read.chomp =~ /no program input from stdin allowed in tainted mode \(SecurityError\)/)
    end

    ENV['RUBYOPT'] = '-T4'
    ruby do |w, r, e|
    end

    ENV['RUBYOPT'] = '-KN -Eus-ascii'
    ruby('-KU', '-Eutf-8') do |w, r, e|
      w.puts "p '\u3042'"
      w.close
      assert_equal("\"\u3042\"", r.read.chomp.force_encoding(Encoding.find('utf-8')))
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

    t = Tempfile.new(["test_ruby_test_rubyoption", ".rb"])
    t.puts "p 1"
    t.close

    @verbose = $VERBOSE
    $VERBOSE = nil

    ENV['PATH'] = File.dirname(t.path)

    ruby('-S', File.basename(t.path)) do |w, r, e|
#      assert_equal('', e.read)
#      assert_equal('1', r.read)
    end

    ENV['RUBYPATH'] = File.dirname(t.path)

    ruby('-S', File.basename(t.path)) do |w, r, e|
#      assert_equal('', e.read)
#      assert_equal('1', r.read)
    end

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
    t.close(true) if t
    $VERBOSE = @verbose
  end

  def test_shebang
    ruby do |w, r, e|
      w.print "#! /test_r_u_b_y_test_r_u_b_y_options_foobarbazqux\r\np 1\r\n"
      w.close
      assert(e.read.chomp =~ /Can't exec \/test_r_u_b_y_test_r_u_b_y_options_foobarbazqux \(fatal\)/)
      assert_equal('', r.read.chomp)
    end

    ruby do |w, r, e|
      w.print "#! /test_r_u_b_y_test_r_u_b_y_options_foobarbazqux -foo -bar\r\np 1\r\n"
      w.close
      assert(e.read.chomp =~ /Can't exec \/test_r_u_b_y_test_r_u_b_y_options_foobarbazqux \(fatal\)/)
      assert_equal('', r.read.chomp)
    end

    ruby do |w, r, e|
      w.print "#!ruby -KU -Eutf-8\r\np \"\u3042\"\r\n"
      w.close
      assert_equal('', e.read.chomp)
      assert_equal("\"\u3042\"", r.read.chomp.force_encoding(Encoding.find('utf-8')))
    end
  end

  def test_sflag
    ruby('-', '-abc', '-def=foo', '-ghi-jkl', '--', '-xyz') do |w, r, e|
      w.print "#!ruby -s\np [$abc, $def, $ghi_jkl, $xyz]\n"
      w.close
      assert_equal('', e.read)
      assert_equal('[true, "foo", true, nil]', r.read.chomp)
    end

    ruby('-', '-#') do |w, r, e|
      w.print "#!ruby -s\n"
      w.close
      assert(e.read.chomp =~ /invalid name for global variable - -# \(NameError\)/)
      assert_equal('', r.read.chomp)
    end

    ruby('-', '-#=foo') do |w, r, e|
      w.print "#!ruby -s\n"
      w.close
      assert(e.read.chomp =~ /invalid name for global variable - -# \(NameError\)/)
      assert_equal('', r.read.chomp)
    end
  end
end

else

assert(false, "cannot test in win32")

end
