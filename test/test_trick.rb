require "test/unit"
require "ripper"
require "envutil"

# This is a test suite for TRICK entries, joke Ruby program contest.
# The programs are very unusual, and not practical.
# Feel free to comment them out if they bother you.
# I'll appreciate it if you could notify mame <mame@ruby-lang.org>

class TestTRICK2013 < Test::Unit::TestCase
  def test_kinaba
    src = File.join(__dir__, "../sample/trick2013/kinaba/entry.rb")
    expected = [*" ".."~"].join("") # all ASCII printables
    assert_in_out_err(["-W0", src], "", [expected])
    assert_equal(expected, File.read(src).chomp.chars.sort.join)
  end

  def test_mame
    src = File.join(__dir__, "../sample/trick2013/mame/entry.rb")
    ignore_dsp = "def open(_file, _mode); s = ''; def s.flush; self;end; yield s; end;"
    assert_in_out_err(["-W0"], ignore_dsp + File.read(src), File.read(src).lines(chomp: true), timeout: 60)
  end

  def test_shinh
    src = File.join(__dir__, "../sample/trick2013/shinh/entry.rb")
    assert_in_out_err(["-W0", src], "", [])
  end

  def test_yhara
    src = File.join(__dir__, "../sample/trick2013/yhara/entry.rb")
    assert_in_out_err(["-W0", src], "", ["JUST ANOTHER RUBY HACKER"])
  end
end

class TestTRICK2015 < Test::Unit::TestCase
  def test_kinaba
    src = File.join(__dir__, "../sample/trick2015/kinaba/entry.rb")

    # calculate the first 10000 digits of Pi
    n = 10000
    a = b = 10 ** n
    (n * 8 + 1).step(3, -2) do |i|
        a = (i / 2) * (a + b * 2) / i
    end
    pi = "3#{ a - b }"

    assert_in_out_err(["-W0", src], "", [pi], timeout: 60)
    assert_equal(pi[0, 242], Ripper.tokenize(File.read(src)).grep(/\S/).map{|t|t.size%10}.join)
  end

  def test_ksk_1
    src = File.join(__dir__, "../sample/trick2015/ksk_1/entry.rb")

    # calculate Collatz sequence
    s = ["27"]
    n = 27
    until n == 1
      n = n.even? ? n / 2 : n * 3 + 1
      s << n.to_s
    end

    assert_in_out_err(["-W0", src, "27"], "", s)
  end

  def test_monae
    src = File.join(__dir__, "../sample/trick2015/monae/entry.rb")

    code = File.read(src)
    expected = code.lines(chomp: true) + (0..15).map { "" }
    code.lines.each_with_index do |s, y|
      y += 16
      s.chomp.chars.each_with_index do |c, x|
        x += 16
        expected[y] << " " while expected[y].size < x
        expected[y][x] = c if c != " "
      end
    end
    expected = /\A#{ expected.map {|s| "#{ Regexp.quote(s) }\s*\n" }.join }\z/

    assert_in_out_err(["-W0", src], "", expected)
  end

  def test_eregon
    src = File.join(__dir__, "../sample/trick2015/eregon/entry.rb")

    assert_in_out_err(["-W0", src], "", <<END.lines(chomp: true))
1 9 4 2 3 8 7 6 5
3 7 2 6 5 1 4 8 9
8 5 6 7 4 9 2 3 1
7 8 1 3 6 4 5 9 2
4 2 3 9 7 5 8 1 6
5 6 9 8 1 2 3 7 4
6 4 8 1 2 7 9 5 3
9 3 5 4 8 6 1 2 7
2 1 7 5 9 3 6 4 8

1 9 7 2 3 8 4 6 5
3 4 2 6 5 1 7 8 9
8 5 6 7 4 9 2 3 1
7 1 8 3 6 4 5 9 2
4 2 3 9 7 5 8 1 6
5 6 9 8 1 2 3 7 4
6 8 4 1 2 7 9 5 3
9 3 5 4 8 6 1 2 7
2 7 1 5 9 3 6 4 8

END
  end

  def test_ksk_2
    src = File.join(__dir__, "../sample/trick2015/ksk_2/entry.rb")

    inp = <<END
c
c This is a sample input file.
c
p cnf 3 5
 1 -2  3 0
-1  2 0
-2 -3 0
 1  2 -3 0
 1  3 0
END

    assert_in_out_err(["-W0", src], inp, ["s SATISFIABLE", "v 1 2 -3"])
  end
end

class TestTRICK2018 < Test::Unit::TestCase
  def test_01_kinaba
    src = File.join(__dir__, "../sample/trick2018/01-kinaba/entry.rb")

    assert_in_out_err(["-W0", src], "", [])
  end

  def test_02_mame
    src = File.join(__dir__, "../sample/trick2018/02-mame/entry.rb")

    ignore_sleep = "def sleep(_); end;"
    assert_in_out_err(["-W0"], ignore_sleep + File.read(src)) do |stdout, _stderr, _status|
      code = stdout.join("\n") + "\n"
      expected = code.lines(chomp: true)
      assert_in_out_err(["-W0"], ignore_sleep + code, expected)
    end
  end

  def test_03_tompng
    src = File.join(__dir__, "../sample/trick2018/03-tompng/entry.rb")

    # only syntax check because it requires chunky_png
    assert_in_out_err(["-W0", "-c", src], "", ["Syntax OK"])
  end

  def test_04_colin
    src = File.join(__dir__, "../sample/trick2018/04-colin/entry.rb")

    code = "# encoding: UTF-8\n" + File.read(src, encoding: "UTF-8") + <<END
\u{1F914} "Math" do
  \u{1F914} "Addition" do
    \u{1F914} "One plus one equals two.",
      1+1 == 2
    \u{1F914} "One plus one equals eleven. (This should fail.)",
      1+1 == 11
  end

  \u{1F914} "Subtraction" do
    \u{1F914} "One minus one equals zero.",
      1-1 == 0
    \u{1F914} "Ten minus one equal nine.",
      10-1 == 9
  end
end
END
    assert_in_out_err(["-W0"], code, <<END.lines(chomp: true), encoding: "UTF-8")
Math
    Addition
        One plus one equals two.
        \u{1F6AB} One plus one equals eleven. (This should fail.)
    Subtraction
        One minus one equals zero.
        Ten minus one equal nine.
END
  end

  def test_05_tompng
    src = File.join(__dir__, "../sample/trick2018/05-tompng/entry.rb")

    # only syntax check because it generates 3D model data
    assert_in_out_err(["-W0", "-c", src], "", ["Syntax OK"])
  end
end
