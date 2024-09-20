# frozen_string_literal: false

require "test/unit"
require "ripper"
require "envutil"
require "stringio"

# This is a test suite for TRICK entries, joke Ruby program contest.
# The programs are very unusual, and not practical.
# Feel free to comment them out if they bother you.
# I'll appreciate it if you could notify mame <mame@ruby-lang.org>

class TestTRICK2013 < Test::Unit::TestCase
  def test_kinaba
    src = File.join(__dir__, "../sample/trick2013/kinaba/entry.rb")
    expected = [*" ".."~"].join("") # all ASCII printables
    assert_in_out_err(["-W0", "--disable-frozen-string-literal", src], "", [expected])
    assert_equal(expected, File.read(src).chomp.chars.sort.join)
  end

  def test_mame
    src = File.join(__dir__, "../sample/trick2013/mame/entry.rb")
    ignore_dsp = "def open(_file, _mode); s = ''; def s.flush; self;end; yield s; end;"
    assert_in_out_err(["-W0", "--disable-frozen-string-literal"], ignore_dsp + File.read(src), File.read(src).lines(chomp: true), timeout: 60)
  end

  def test_shinh
    src = File.join(__dir__, "../sample/trick2013/shinh/entry.rb")
    assert_in_out_err(["-W0", "--disable-frozen-string-literal", src], "", [])
  end

  def test_yhara
    src = File.join(__dir__, "../sample/trick2013/yhara/entry.rb")
    assert_in_out_err(["-W0", "--disable-frozen-string-literal", src], "", ["JUST ANOTHER RUBY HACKER"])
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

    assert_in_out_err(["-W0", "--disable-frozen-string-literal", src], "", [pi], timeout: 60)
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

    assert_in_out_err(["-W0", "--disable-frozen-string-literal", src, "27"], "", s)
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

    assert_in_out_err(["-W0", "--disable-frozen-string-literal", src], "", expected)
  end

  def test_eregon
    src = File.join(__dir__, "../sample/trick2015/eregon/entry.rb")

    assert_in_out_err(["-W0", "--disable-frozen-string-literal", src], "", <<END.lines(chomp: true))
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

    assert_in_out_err(["-W0", "--disable-frozen-string-literal", src], inp, ["s SATISFIABLE", "v 1 2 -3"])
  end
end

class TestTRICK2018 < Test::Unit::TestCase
  def test_01_kinaba
    src = File.join(__dir__, "../sample/trick2018/01-kinaba/entry.rb")

    assert_in_out_err(["-W0", "--disable-frozen-string-literal", src], "", [])
  end

  def test_02_mame
    src = File.join(__dir__, "../sample/trick2018/02-mame/entry.rb")

    ignore_sleep = "def sleep(_); end;"
    assert_in_out_err(["-W0", "--disable-frozen-string-literal"], ignore_sleep + File.read(src)) do |stdout, _stderr, _status|
      code = stdout.join("\n") + "\n"
      expected = code.lines(chomp: true)
      assert_in_out_err(["-W0", "--disable-frozen-string-literal"], ignore_sleep + code, expected)
    end
  end

  def test_03_tompng
    src = File.join(__dir__, "../sample/trick2018/03-tompng/entry.rb")

    # only syntax check because it requires chunky_png
    assert_in_out_err(["-W0", "--disable-frozen-string-literal", "-c", src], "", ["Syntax OK"])
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
    assert_in_out_err(["-W0", "--disable-frozen-string-literal"], code, <<END.lines(chomp: true), encoding: "UTF-8")
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
    assert_in_out_err(["-W0", "--disable-frozen-string-literal", "-c", src], "", ["Syntax OK"])
  end
end

class TestTRICK2022 < Test::Unit::TestCase
  def test_01_tompng
    src = File.join(__dir__, "../sample/trick2022/01-tompng/entry.rb")

    # only syntax check because it requires matrix
    assert_in_out_err(["-W0", "--disable-frozen-string-literal", "-c", src], "", ["Syntax OK"])
  end

  def test_02_tompng
    src = File.join(__dir__, "../sample/trick2022/02-tompng/entry.rb")

    # only syntax check because it works as a web server
    assert_in_out_err(["-W0", "--disable-frozen-string-literal", "-c", src], "", ["Syntax OK"])
  end

  def test_03_mame
    src = File.join(__dir__, "../sample/trick2022/03-mame/entry.rb")

    # TODO
    assert_in_out_err(["-W0", "--disable-frozen-string-literal", "-c", src], "", ["Syntax OK"])
  end
end

class TestRubyKaigi2023🥢 < Test::Unit::TestCase
  CHOPSTICKS = [<<~'0', <<~'1'] # by mame
  BEGIN{q=:Ruby};p||=:Enjoy;END{puts p,q||2023}
  0
  q=print(q||"/:|}\n")||p&&:@Matsumoto;p=:Kaigi
  1

  def test_chopsticks_0
    assert_in_out_err(%w[-W0], CHOPSTICKS[0], %w[Enjoy Ruby])
  end

  def test_chopsticks_1
    assert_in_out_err(%w[-W0], CHOPSTICKS[1], %w[/:|}])
  end

  def test_chopsticks_0_1
    assert_in_out_err(%w[-W0], "#{CHOPSTICKS[0]}\n#{CHOPSTICKS[1]}", %w[RubyKaigi @Matsumoto])
  end

  def test_chopsticks_1_0
    assert_in_out_err(%w[-W0], "#{CHOPSTICKS[1]}\n#{CHOPSTICKS[0]}", %w[RubyKaigi 2023])
  end
end

# https://github.com/mame/all-ruby-quine
class TestAllRubyQuine < Test::Unit::TestCase
  def test_all_ruby_quine
    stdout_bak = $stdout
    $stdout = StringIO.new
    verbose_bak = $VERBOSE
    $VERBOSE = nil
    src = File.read(File.join(__dir__, "../sample/all-ruby-quine.rb"))

    eval(src)

    out = $stdout.string.lines(chomp: true)
    $stdout = stdout_bak

    # cheat OCR
    font = {
      "-" => 0x7ffffffffffe03fffffffffff, "." => 0x7fffffffffffffffffffc7f8f, "_" => 0x7fffffffffffffffffffff800,
      "0" => 0x6030e03e07c0f81f03e038603, "1" => 0x70fc1f23fc7f8ff1fe3fc7c01, "2" => 0x4011f1fe3fc7e1f0f87c3f800,
      "3" => 0x4031e3fe3f8e03fe3fe078c03, "4" => 0x783e0788e318e31c6003f1fe3, "5" => 0x0001fe3fc7f801fe1fe078401,
      "6" => 0x78083e3fc7f8011e03e038401, "7" => 0x000fe1fc3f0fc3f0fc3f0fc3f, "8" => 0x4011f03e238e038e23e07c401,
      "9" => 0x4010e03e03c400ff1fe078401, "a" => 0x7fffff00c787f88003e078408, "b" => 0x0ff1fe3fc408701f03e078001,
      "c" => 0x7fffff8063c0ff1fe3fe3c601, "d" => 0x7f8ff1fe3004781f03e038408,
    }.invert
    out = (0...out.first.size / 15).map do |i|
      font[(3..11).map {|j| out[j][i * 15 + 5, 11] }.join.gsub(/\S/, "#").tr("# ", "10").to_i(2)]
    end.join

    assert_equal(RUBY_VERSION, out)
  ensure
    $stdout = stdout_bak
    $VERBOSE = verbose_bak
  end
end
