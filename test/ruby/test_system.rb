require 'test/unit'
$:.replace([File.dirname(File.expand_path(__FILE__))] | $:)
require 'envutil'

$KCODE = 'none'

class TestSystem < Test::Unit::TestCase
  def valid_syntax?(code, fname)
    eval("BEGIN {return true}\n#{code}", nil, fname, 0)
  end

  def test_system
    ruby = EnvUtil.rubybin
    assert_equal("foobar\n", `echo foobar`)
    assert_equal('foobar', `#{ruby} -e 'print "foobar"'`)

    tmp = open("script_tmp", "w")
    tmp.print "print $zzz\n";
    tmp.close

    assert_equal('true', `#{ruby} -s script_tmp -zzz`)
    assert_equal('555', `#{ruby} -s script_tmp -zzz=555`)

    tmp = open("script_tmp", "w")
    tmp.print "#! /usr/local/bin/ruby -s\n";
    tmp.print "print $zzz\n";
    tmp.close

    assert_equal('678', `#{ruby} script_tmp -zzz=678`)

    tmp = open("script_tmp", "w")
    tmp.print "this is a leading junk\n";
    tmp.print "#! /usr/local/bin/ruby -s\n";
    tmp.print "print $zzz\n";
    tmp.print "__END__\n";
    tmp.print "this is a trailing junk\n";
    tmp.close

    assert_equal('nil', `#{ruby} -x script_tmp`)
    assert_equal('555', `#{ruby} -x script_tmp -zzz=555`)

    tmp = open("script_tmp", "w")
    for i in 1..5
      tmp.print i, "\n"
    end
    tmp.close

    `#{ruby} -i.bak -pe 'sub(/^[0-9]+$/){$&.to_i * 5}' script_tmp`
    tmp = open("script_tmp", "r")
    while tmp.gets
      assert_equal(0, $_.to_i % 5)
    end
    tmp.close

    File.unlink "script_tmp" or `/bin/rm -f "script_tmp"`
    File.unlink "script_tmp.bak" or `/bin/rm -f "script_tmp.bak"`

    if (dir = File.dirname(File.dirname($0))) == '.'
      dir = ""
    else
      dir << "/"
    end

    for script in Dir["#{dir}{lib,sample,ext}/**/*.rb"]
      assert_nothing_raised(Exception) do
        valid_syntax? IO::read(script), script
      end
    end
  end
end
