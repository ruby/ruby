require 'test/unit'
require 'tmpdir'
require_relative 'envutil'

class TestSystem < Test::Unit::TestCase
  def valid_syntax?(code, fname)
    code = code.dup.force_encoding("ascii-8bit")
    code.sub!(/\A(?:\xef\xbb\xbf)?(\s*\#.*$)*(\n)?/n) {
      "#$&#{"\n" if $1 && !$2}BEGIN{throw tag, :ok}\n"
    }
    code.force_encoding("us-ascii")
    catch {|tag| eval(code, binding, fname, 0)}
  rescue SyntaxError
    false
  end

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
      end
    }
  end

  def test_syntax
    assert_nothing_raised(Exception) do
      for script in Dir[File.expand_path("../../../{lib,sample,ext,test}/**/*.rb", __FILE__)].sort
        assert(valid_syntax?(IO::read(script), script))
      end
    end
  end

  def test_empty_evstr
    assert_equal("", eval('"#{}"', nil, __FILE__, __LINE__), "[ruby-dev:25113]")
  end
end
