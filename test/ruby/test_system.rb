# frozen_string_literal: false
require 'test/unit'
require 'tmpdir'

class TestSystem < Test::Unit::TestCase
  def test_system
    ruby = EnvUtil.rubybin
    assert_equal("foobar\n", `echo foobar`)
    assert_equal('foobar', `#{ruby} -e 'print "foobar"'`)

    Dir.mktmpdir("ruby_script_tmp") {|tmpdir|
      tmpfilename = "#{tmpdir}/ruby_script_tmp.#{$$}"

      tmp = open(tmpfilename, "w")
      tmp.print "print $zzz\n";
      tmp.close

      assert_equal('true', `#{ruby} -s #{tmpfilename} -zzz`)
      assert_equal('555', `#{ruby} -s #{tmpfilename} -zzz=555`)

      tmp = open(tmpfilename, "w")
      tmp.print "#! /usr/local/bin/ruby -s\n";
      tmp.print "print $zzz\n";
      tmp.close

      assert_equal('678', `#{ruby} #{tmpfilename} -zzz=678`)

      tmp = open(tmpfilename, "w")
      tmp.print "this is a leading junk\n";
      tmp.print "#! /usr/local/bin/ruby -s\n";
      tmp.print "print $zzz if defined? $zzz\n";
      tmp.print "__END__\n";
      tmp.print "this is a trailing junk\n";
      tmp.close

      assert_equal('', `#{ruby} -x #{tmpfilename}`)
      assert_equal('555', `#{ruby} -x #{tmpfilename} -zzz=555`)

      tmp = open(tmpfilename, "w")
      tmp.print "#! /non/exist\\interpreter?/./to|be:ignored\n";
      tmp.print "this is a leading junk\n";
      tmp.print "#! /usr/local/bin/ruby -s\n";
      tmp.print "print $zzz if defined? $zzz\n";
      tmp.print "__END__\n";
      tmp.print "this is a trailing junk\n";
      tmp.close

      assert_equal('', `#{ruby} #{tmpfilename}`)
      assert_equal('555', `#{ruby} #{tmpfilename} -zzz=555`)

      tmp = open(tmpfilename, "w")
      for i in 1..5
        tmp.print i, "\n"
      end
      tmp.close

      `#{ruby} -i.bak -pe '$_.sub!(/^[0-9]+$/){$&.to_i * 5}' #{tmpfilename}`
      tmp = open(tmpfilename, "r")
      while tmp.gets
        assert_equal(0, $_.to_i % 5)
      end
      tmp.close

      File.unlink tmpfilename or `/bin/rm -f "#{tmpfilename}"`
      File.unlink "#{tmpfilename}.bak" or `/bin/rm -f "#{tmpfilename}.bak"`

      if /mswin|mingw/ =~ RUBY_PLATFORM
        testname = '[ruby-dev:38588]'
        batch = "batch_tmp.#{$$}"
        tmpfilename = "#{tmpdir}/#{batch}.bat"
        open(tmpfilename, "wb") {|f| f.print "\r\n"}
        assert(system(tmpfilename), testname)
        assert(system("#{tmpdir}/#{batch}"), testname)
        assert(system(tmpfilename, "1"), testname)
        assert(system("#{tmpdir}/#{batch}", "1"), testname)
        begin
          path = ENV["PATH"]
          ENV["PATH"] = "#{tmpdir.tr(File::SEPARATOR, File::ALT_SEPARATOR)}#{File::PATH_SEPARATOR + path if path}"
          assert(system("#{batch}.bat"), testname)
          assert(system(batch), testname)
          assert(system("#{batch}.bat", "1"), testname)
          assert(system(batch, "1"), testname)
        ensure
          ENV["PATH"] = path
        end
        File.unlink tmpfilename

        testname = '[ruby-core:44505]'
        assert_match(/Windows/, `ver`, testname)
        assert_equal 0, $?.to_i, testname
      end
    }
  end

  def test_system_at
    if /mswin|mingw/ =~ RUBY_PLATFORM
      bug4393 = '[ruby-core:35218]'

      # @ + builtin command
      assert_equal("foo\n", `@echo foo`, bug4393);
      assert_equal("foo\n", `@@echo foo`, bug4393);
      assert_equal("@@foo\n", `@@echo @@foo`, bug4393);

      # @ + non builtin command
      Dir.mktmpdir("ruby_script_tmp") {|tmpdir|
        tmpfilename = "#{tmpdir}/ruby_script_tmp.#{$$}"

        tmp = open(tmpfilename, "w")
        tmp.print "foo\nbar\nbaz\n@foo";
        tmp.close

        assert_match(/\Abar\nbaz\n?\z/, `@@findstr "ba" #{tmpfilename.gsub("/", "\\")}`, bug4393);
      }
    end
  end

  def test_system_redirect_win
    if /mswin|mingw/ !~ RUBY_PLATFORM
      return
    end

    Dir.mktmpdir("ruby_script_tmp") do |tmpdir|
      cmd = nil
      message = proc do
        [
         '[ruby-talk:258939]',
         "out.txt:",
         *File.readlines("out.txt").map{|s|"  "+s.inspect},
         "err.txt:",
         *File.readlines("err.txt").map{|s|"  "+s.inspect},
         "system(#{cmd.inspect})"
        ].join("\n")
      end
      class << message
        alias to_s call
      end
      Dir.chdir(tmpdir) do
        open("input.txt", "w") {|f| f.puts "BFI3CHL671"}
        cmd = "%WINDIR%/system32/find.exe \"BFI3CHL671\" input.txt > out.txt 2>err.txt"
        assert_equal(true, system(cmd), message)
        cmd = "\"%WINDIR%/system32/find.exe\" \"BFI3CHL671\" input.txt > out.txt 2>err.txt"
        assert_equal(true, system(cmd), message)
        cmd = "\"%WINDIR%/system32/find.exe BFI3CHL671\" input.txt > out.txt 2>err.txt"
        assert_equal(false, system(cmd), message)
      end
    end
  end

  def test_empty_evstr
    assert_equal("", eval('"#{}"', nil, __FILE__, __LINE__), "[ruby-dev:25113]")
  end

  def test_fallback_to_sh
    Dir.mktmpdir("ruby_script_tmp") {|tmpdir|
      tmpfilename = "#{tmpdir}/ruby_script_tmp.#{$$}"
      open(tmpfilename, "w") {|f|
        f.puts ": ;"
        f.chmod(0755)
      }
      assert_equal(true, system(tmpfilename), '[ruby-core:32745]')
    }
  end if File.executable?("/bin/sh")

  def test_system_exception
    ruby = EnvUtil.rubybin
    assert_nothing_raised do
      system('feature_14235', exception: false)
    end
    assert_nothing_raised do
      system(ruby, "-e", "abort", exception: false)
    end
    assert_nothing_raised do
      system("'#{ruby}' -e abort", exception: false)
    end
    assert_raise(Errno::ENOENT) do
      system('feature_14235', exception: true)
    end
    assert_raise_with_message(RuntimeError, /\ACommand failed with exit /) do
      system(ruby, "-e", "abort", exception: true)
    end
    assert_raise_with_message(RuntimeError, /\ACommand failed with exit /) do
      system("'#{ruby}' -e abort", exception: true)
    end
  end

  def test_system_exception_nonascii
    Dir.mktmpdir("ruby_script_tmp") do |tmpdir|
      name = "\u{30c6 30b9 30c8}"
      tmpfilename = "#{tmpdir}/#{name}.cmd"
      message = /#{name}\.cmd/
      assert_raise_with_message(Errno::ENOENT, message) do
        system(tmpfilename, exception: true)
      end
      open(tmpfilename, "w") {|f|
        f.print "@" if /mingw|mswin/ =~ RUBY_PLATFORM
        f.puts "exit 127"
        f.chmod(0755)
      }
      assert_raise_with_message(RuntimeError, message) do
        system(tmpfilename, exception: true)
      end
    end
  end
end
