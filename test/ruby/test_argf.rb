# frozen_string_literal: false
require 'test/unit'
require 'timeout'
require 'tmpdir'
require 'tempfile'
require 'fileutils'

class TestArgf < Test::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir
    @tmp_count = 0
    @t1 = make_tempfile0("argf-foo")
    @t1.binmode
    @t1.puts "1"
    @t1.puts "2"
    @t1.close
    @t2 = make_tempfile0("argf-bar")
    @t2.binmode
    @t2.puts "3"
    @t2.puts "4"
    @t2.close
    @t3 = make_tempfile0("argf-baz")
    @t3.binmode
    @t3.puts "5"
    @t3.puts "6"
    @t3.close
  end

  def teardown
    FileUtils.rmtree(@tmpdir)
  end

  def make_tempfile0(basename)
    @tmp_count += 1
    open("#{@tmpdir}/#{basename}-#{@tmp_count}", "w")
  end

  def make_tempfile(basename = "argf-qux")
    t = make_tempfile0(basename)
    t.puts "foo"
    t.puts "bar"
    t.puts "baz"
    t.close
    t
  end

  def ruby(*args, external_encoding: Encoding::UTF_8)
    args = ['-e', '$>.write($<.read)'] if args.empty?
    ruby = EnvUtil.rubybin
    f = IO.popen([ruby] + args, 'r+', external_encoding: external_encoding)
    yield(f)
  ensure
    f.close unless !f || f.closed?
  end

  def no_safe_rename
    /cygwin|mswin|mingw|bccwin/ =~ RUBY_PLATFORM
  end

  def assert_src_expected(src, args = nil, line: caller_locations(1, 1)[0].lineno+1)
    args ||= [@t1.path, @t2.path, @t3.path]
    expected = src.split(/^/)
    ruby('-e', src, *args) do |f|
      expected.each_with_index do |e, i|
        /#=> *(.*)/ =~ e or next
        a = f.gets
        assert_not_nil(a, "[ruby-dev:34445]: remained")
        assert_equal($1, a.chomp, "[ruby-dev:34445]: line #{line+i}")
      end
    end
  end

  def test_argf
    assert_src_expected("#{<<~"{#"}\n#{<<~'};'}")
    {#
      a = ARGF
      b = a.dup
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["1", 1, "1", 1]
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["2", 2, "2", 2]
      a.rewind
      b.rewind
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["1", 1, "1", 1]
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["2", 2, "2", 2]
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["3", 3, "3", 3]
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["4", 4, "4", 4]
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["5", 5, "5", 5]
      a.rewind
      b.rewind
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["5", 5, "5", 5]
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["6", 6, "6", 6]
    };
  end

  def test_lineno
    assert_src_expected("#{<<~"{#"}\n#{<<~'};'}")
    {#
      a = ARGF
      a.gets; p($.) #=> 1
      a.gets; p($.) #=> 2
      a.gets; p($.) #=> 3
      a.rewind; p($.) #=> 3
      a.gets; p($.) #=> 3
      a.gets; p($.) #=> 4
      a.rewind; p($.) #=> 4
      a.gets; p($.) #=> 3
      a.lineno = 1000; p($.) #=> 1000
      a.gets; p($.) #=> 1001
      a.gets; p($.) #=> 1002
      $. = 2000
      a.gets; p($.) #=> 2001
      a.gets; p($.) #=> 2001
    };
  end

  def test_lineno2
    assert_src_expected("#{<<~"{#"}\n#{<<~'};'}")
    {#
      a = ARGF.dup
      a.gets; p($.) #=> 1
      a.gets; p($.) #=> 2
      a.gets; p($.) #=> 1
      a.rewind; p($.) #=> 1
      a.gets; p($.) #=> 1
      a.gets; p($.) #=> 2
      a.gets; p($.) #=> 1
      a.lineno = 1000; p($.) #=> 1
      a.gets; p($.) #=> 2
      a.gets; p($.) #=> 2
      $. = 2000
      a.gets; p($.) #=> 2000
      a.gets; p($.) #=> 2000
    };
  end

  def test_lineno3
    expected = %w"1 1 1 2 2 2 3 3 1 4 4 2"
    assert_in_out_err(["-", @t1.path, @t2.path],
                      "#{<<~"{#"}\n#{<<~'};'}", expected, [], "[ruby-core:25205]")
    {#
      ARGF.each do |line|
        puts [$., ARGF.lineno, ARGF.file.lineno]
      end
    };
  end

  def test_new_lineno_each
    f = ARGF.class.new(@t1.path, @t2.path, @t3.path)
    result = []
    f.each {|line| result << [f.lineno, line]; break if result.size == 3}
    assert_equal(3, f.lineno)
    assert_equal((1..3).map {|i| [i, "#{i}\n"]}, result)

    f.rewind
    assert_equal(2, f.lineno)
  ensure
    f.close
  end

  def test_new_lineno_each_char
    f = ARGF.class.new(@t1.path, @t2.path, @t3.path)
    f.each_char.to_a
    assert_equal(0, f.lineno)
  ensure
    f.close
  end

  def test_inplace
    assert_in_out_err(["-", @t1.path, @t2.path, @t3.path],
                      "#{<<~"{#"}\n#{<<~'};'}")
    {#
      ARGF.inplace_mode = '.bak'
      while line = ARGF.gets
        puts line.chomp + '.new'
      end
    };
    assert_equal("1.new\n2.new\n", File.read(@t1.path))
    assert_equal("3.new\n4.new\n", File.read(@t2.path))
    assert_equal("5.new\n6.new\n", File.read(@t3.path))
    assert_equal("1\n2\n", File.read(@t1.path + ".bak"))
    assert_equal("3\n4\n", File.read(@t2.path + ".bak"))
    assert_equal("5\n6\n", File.read(@t3.path + ".bak"))
  end

  def test_inplace2
    assert_in_out_err(["-", @t1.path, @t2.path, @t3.path],
                      "#{<<~"{#"}\n#{<<~'};'}")
    {#
      ARGF.inplace_mode = '.bak'
      puts ARGF.gets.chomp + '.new'
      puts ARGF.gets.chomp + '.new'
      p ARGF.inplace_mode
      ARGF.inplace_mode = nil
      puts ARGF.gets.chomp + '.new'
      puts ARGF.gets.chomp + '.new'
      p ARGF.inplace_mode
      ARGF.inplace_mode = '.bak'
      puts ARGF.gets.chomp + '.new'
      p ARGF.inplace_mode
      ARGF.inplace_mode = nil
      puts ARGF.gets.chomp + '.new'
    };
    assert_equal("1.new\n2.new\n\".bak\"\n3.new\n4.new\nnil\n", File.read(@t1.path))
    assert_equal("3\n4\n", File.read(@t2.path))
    assert_equal("5.new\n\".bak\"\n6.new\n", File.read(@t3.path))
    assert_equal("1\n2\n", File.read(@t1.path + ".bak"))
    assert_equal(false, File.file?(@t2.path + ".bak"))
    assert_equal("5\n6\n", File.read(@t3.path + ".bak"))
  end

  def test_inplace3
    assert_in_out_err(["-i.bak", "-", @t1.path, @t2.path, @t3.path],
                      "#{<<~"{#"}\n#{<<~'};'}")
    {#
      puts ARGF.gets.chomp + '.new'
      puts ARGF.gets.chomp + '.new'
      p $-i
      $-i = nil
      puts ARGF.gets.chomp + '.new'
      puts ARGF.gets.chomp + '.new'
      p $-i
      $-i = '.bak'
      puts ARGF.gets.chomp + '.new'
      p $-i
      $-i = nil
      puts ARGF.gets.chomp + '.new'
    };
    assert_equal("1.new\n2.new\n\".bak\"\n3.new\n4.new\nnil\n", File.read(@t1.path))
    assert_equal("3\n4\n", File.read(@t2.path))
    assert_equal("5.new\n\".bak\"\n6.new\n", File.read(@t3.path))
    assert_equal("1\n2\n", File.read(@t1.path + ".bak"))
    assert_equal(false, File.file?(@t2.path + ".bak"))
    assert_equal("5\n6\n", File.read(@t3.path + ".bak"))
  end

  def test_inplace_rename_impossible
    t = make_tempfile

    assert_in_out_err(["-", t.path], "#{<<~"{#"}\n#{<<~'};'}") do |r, e|
      {#
        ARGF.inplace_mode = '/\\\\:'
        while line = ARGF.gets
          puts line.chomp + '.new'
        end
      };
      assert_match(/Can't rename .* to .*: .*. skipping file/, e.first) #'
      assert_equal([], r)
      assert_equal("foo\nbar\nbaz\n", File.read(t.path))
    end

    base = "argf-\u{30c6 30b9 30c8}"
    name = "#{@tmpdir}/#{base}"
    File.write(name, "foo")
    argf = ARGF.class.new(name)
    argf.inplace_mode = '/\\:'
    assert_warning(/#{base}/) {argf.gets}
  end

  def test_inplace_nonascii
    ext = Encoding.default_external or
      skip "no default external encoding"
    t = nil
    ["\u{3042}", "\u{e9}"].any? do |n|
      t = make_tempfile(n.encode(ext))
    rescue Encoding::UndefinedConversionError
    end
    t or skip "no name to test"
    assert_in_out_err(["-i.bak", "-", t.path],
                      "#{<<~"{#"}\n#{<<~'};'}")
    {#
      puts ARGF.gets.chomp + '.new'
      puts ARGF.gets.chomp + '.new'
      puts ARGF.gets.chomp + '.new'
    };
    assert_equal("foo.new\n""bar.new\n""baz.new\n", File.read(t.path))
    assert_equal("foo\n""bar\n""baz\n", File.read(t.path + ".bak"))
  end

  def test_inplace_no_backup
    t = make_tempfile

    assert_in_out_err(["-", t.path], "#{<<~"{#"}\n#{<<~'};'}") do |r, e|
      {#
        ARGF.inplace_mode = ''
        while line = ARGF.gets
          puts line.chomp + '.new'
        end
      };
      if no_safe_rename
        assert_match(/Can't do inplace edit without backup/, e.join) #'
      else
        assert_equal([], e)
        assert_equal([], r)
        assert_equal("foo.new\nbar.new\nbaz.new\n", File.read(t.path))
      end
    end
  end

  def test_inplace_dup
    t = make_tempfile

    assert_in_out_err(["-", t.path], "#{<<~"{#"}\n#{<<~'};'}", [], [])
    {#
      ARGF.inplace_mode = '.bak'
      f = ARGF.dup
      while line = f.gets
        puts line.chomp + '.new'
      end
    };
    assert_equal("foo.new\nbar.new\nbaz.new\n", File.read(t.path))
  end

  def test_inplace_stdin
    assert_in_out_err(["-", "-"], "#{<<~"{#"}\n#{<<~'};'}", [], /Can't do inplace edit for stdio; skipping/)
    {#
      ARGF.inplace_mode = '.bak'
      f = ARGF.dup
      while line = f.gets
        puts line.chomp + '.new'
      end
    };
  end

  def test_inplace_stdin2
    assert_in_out_err(["-"], "#{<<~"{#"}\n#{<<~'};'}", [], /Can't do inplace edit for stdio/)
    {#
      ARGF.inplace_mode = '.bak'
      while line = ARGF.gets
        puts line.chomp + '.new'
      end
    };
  end

  def test_inplace_invalid_backup
    assert_raise(ArgumentError, '[ruby-dev:50272] [Bug #13960]') {
      ARGF.inplace_mode = "a\0"
    }
  end

  def test_inplace_to_path
    base = "argf-test"
    name = "#{@tmpdir}/#{base}"
    File.write(name, "foo")
    stdout = $stdout
    argf = ARGF.class.new(Struct.new(:to_path).new(name))
    begin
      result = argf.gets
    ensure
      $stdout = stdout
      argf.close
    end
    assert_equal("foo", result)
  end

  def test_inplace_ascii_incompatible_path
    base = "argf-\u{30c6 30b9 30c8}"
    name = "#{@tmpdir}/#{base}"
    File.write(name, "foo")
    stdout = $stdout
    argf = ARGF.class.new(name.encode(Encoding::UTF_16LE))
    assert_raise(Encoding::CompatibilityError) do
      argf.gets
    end
  ensure
    $stdout = stdout
  end

  def test_inplace_suffix_encoding
    base = "argf-\u{30c6 30b9 30c8}"
    name = "#{@tmpdir}/#{base}"
    suffix = "-bak"
    File.write(name, "foo")
    stdout = $stdout
    argf = ARGF.class.new(name)
    argf.inplace_mode = suffix.encode(Encoding::UTF_16LE)
    begin
      argf.each do |s|
        puts "+"+s
      end
    ensure
      $stdout.close unless $stdout == stdout
      $stdout = stdout
    end
    assert_file.exist?(name)
    assert_equal("+foo\n", File.read(name))
    assert_file.not_exist?(name+"-")
    assert_file.exist?(name+suffix)
    assert_equal("foo", File.read(name+suffix))
  end

  def test_inplace_bug_17117
    assert_in_out_err(["-", @t1.path], "#{<<~"{#"}#{<<~'};'}")
    {#
      #!/usr/bin/ruby -pi.bak
      BEGIN {
        GC.start
        arr = []
        1000000.times { |x| arr << "fooo#{x}" }
      }
      puts "hello"
    };
    assert_equal("hello\n1\nhello\n2\n", File.read(@t1.path))
    assert_equal("1\n2\n", File.read("#{@t1.path}.bak"))
  end

  def test_encoding
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        p ARGF.external_encoding.is_a?(Encoding)
        p ARGF.internal_encoding.is_a?(Encoding)
        ARGF.gets
        p ARGF.external_encoding.is_a?(Encoding)
        p ARGF.internal_encoding
      };
      assert_equal("true\ntrue\ntrue\nnil\n", f.read)
    end
  end

  def test_tell
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        begin
          ARGF.binmode
          loop do
            p ARGF.tell
            p ARGF.gets
          end
        rescue ArgumentError
          puts "end"
        end
      };
      a = f.read.split("\n")
      [0, 2, 4, 2, 4, 2, 4].map {|i| i.to_s }.
        zip((1..6).map {|i| '"' + i.to_s + '\n"' } + ["nil"]).flatten.
        each do |x|
        assert_equal(x, a.shift)
      end
      assert_equal('end', a.shift)
    end
  end

  def test_seek
    assert_src_expected("#{<<~"{#"}\n#{<<~'};'}")
    {#
      ARGF.seek(4)
      p ARGF.gets #=> "3\n"
      ARGF.seek(0, IO::SEEK_END)
      p ARGF.gets #=> "5\n"
      ARGF.seek(4)
      p ARGF.gets #=> nil
      begin
        ARGF.seek(0)
      rescue
        puts "end" #=> end
      end
    };
  end

  def test_set_pos
    assert_src_expected("#{<<~"{#"}\n#{<<~'};'}")
    {#
      ARGF.pos = 4
      p ARGF.gets #=> "3\n"
      ARGF.pos = 4
      p ARGF.gets #=> "5\n"
      ARGF.pos = 4
      p ARGF.gets #=> nil
      begin
        ARGF.pos = 4
      rescue
        puts "end" #=> end
      end
    };
  end

  def test_rewind
    assert_src_expected("#{<<~"{#"}\n#{<<~'};'}")
    {#
      ARGF.pos = 4
      ARGF.rewind
      p ARGF.gets #=> "1\n"
      ARGF.pos = 4
      p ARGF.gets #=> "3\n"
      ARGF.pos = 4
      p ARGF.gets #=> "5\n"
      ARGF.pos = 4
      p ARGF.gets #=> nil
      begin
        ARGF.rewind
      rescue
        puts "end" #=> end
      end
    };
  end

  def test_fileno
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        p ARGF.fileno
        ARGF.gets
        ARGF.gets
        p ARGF.fileno
        ARGF.gets
        ARGF.gets
        p ARGF.fileno
        ARGF.gets
        ARGF.gets
        p ARGF.fileno
        ARGF.gets
        begin
          ARGF.fileno
        rescue
          puts "end"
        end
      };
      a = f.read.split("\n")
      fd1, fd2, fd3, fd4, tag = a
      assert_match(/^\d+$/, fd1)
      assert_match(/^\d+$/, fd2)
      assert_match(/^\d+$/, fd3)
      assert_match(/^\d+$/, fd4)
      assert_equal('end', tag)
    end
  end

  def test_to_io
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        8.times do
          p ARGF.to_io
          ARGF.gets
        end
      };
      a = f.read.split("\n")
      f11, f12, f13, f21, f22, f31, f32, f4 = a
      assert_equal(f11, f12)
      assert_equal(f11, f13)
      assert_equal(f21, f22)
      assert_equal(f31, f32)
      assert_match(/\(closed\)/, f4)
      f4.sub!(/ \(closed\)/, "")
      assert_equal(f31, f4)
    end
  end

  def test_eof
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        begin
          8.times do
            p ARGF.eof?
            ARGF.gets
          end
        rescue IOError
          puts "end"
        end
      };
      a = f.read.split("\n")
      (%w(false) + (%w(false true) * 3) + %w(end)).each do |x|
        assert_equal(x, a.shift)
      end
    end

    t1 = open("#{@tmpdir}/argf-hoge", "w")
    t1.binmode
    t1.puts "foo"
    t1.close
    t2 = open("#{@tmpdir}/argf-moge", "w")
    t2.binmode
    t2.puts "bar"
    t2.close
    ruby('-e', 'STDERR.reopen(STDOUT); ARGF.gets; ARGF.skip; p ARGF.eof?', t1.path, t2.path) do |f|
      assert_equal(%w(false), f.read.split(/\n/))
    end
  end

  def test_read
    ruby('-e', "p ARGF.read(8)", @t1.path, @t2.path, @t3.path) do |f|
      assert_equal("\"1\\n2\\n3\\n4\\n\"\n", f.read)
    end
  end

  def test_read2
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        s = ""
        ARGF.read(8, s)
        p s
      };
      assert_equal("\"1\\n2\\n3\\n4\\n\"\n", f.read)
    end
  end

  def test_read2_with_not_empty_buffer
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        s = "0123456789"
        ARGF.read(8, s)
        p s
      };
      assert_equal("\"1\\n2\\n3\\n4\\n\"\n", f.read)
    end
  end

  def test_read3
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        nil while ARGF.gets
        p ARGF.read
        p ARGF.read(0, "")
      };
      assert_equal("nil\n\"\"\n", f.read)
    end
  end

  def test_readpartial
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        s = ""
        begin
          loop do
            s << ARGF.readpartial(1)
            t = ""; ARGF.readpartial(1, t); s << t
            # not empty buffer
            u = "abcdef"; ARGF.readpartial(1, u); s << u
          end
        rescue EOFError
          puts s
        end
      };
      assert_equal("1\n2\n3\n4\n5\n6\n", f.read)
    end
  end

  def test_readpartial2
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}") do |f|
      {#
        s = ""
        begin
          loop do
            s << ARGF.readpartial(1)
            t = ""; ARGF.readpartial(1, t); s << t
          end
        rescue EOFError
          $stdout.binmode
          puts s
        end
      };
      f.binmode
      f.puts("foo")
      f.puts("bar")
      f.puts("baz")
      f.close_write
      assert_equal("foo\nbar\nbaz\n", f.read)
    end
  end

  def test_readpartial_eof_twice
    ruby('-W1', '-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path) do |f|
      {#
        $stderr = $stdout
        print ARGF.readpartial(256)
        ARGF.readpartial(256) rescue p($!.class)
        ARGF.readpartial(256) rescue p($!.class)
      };
      assert_equal("1\n2\nEOFError\nEOFError\n", f.read)
    end
  end

  def test_getc
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        s = ""
        while c = ARGF.getc
          s << c
        end
        puts s
      };
      assert_equal("1\n2\n3\n4\n5\n6\n", f.read)
    end
  end

  def test_getbyte
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        s = []
        while c = ARGF.getbyte
          s << c
        end
        p s
      };
      assert_equal("[49, 10, 50, 10, 51, 10, 52, 10, 53, 10, 54, 10]\n", f.read)
    end
  end

  def test_readchar
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        s = ""
        begin
          while c = ARGF.readchar
            s << c
          end
        rescue EOFError
          puts s
        end
      };
      assert_equal("1\n2\n3\n4\n5\n6\n", f.read)
    end
  end

  def test_readbyte
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        begin
          s = []
          while c = ARGF.readbyte
            s << c
          end
        rescue EOFError
          p s
        end
      };
      assert_equal("[49, 10, 50, 10, 51, 10, 52, 10, 53, 10, 54, 10]\n", f.read)
    end
  end

  def test_each_line
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        s = []
        ARGF.each_line {|l| s << l }
        p s
      };
      assert_equal("[\"1\\n\", \"2\\n\", \"3\\n\", \"4\\n\", \"5\\n\", \"6\\n\"]\n", f.read)
    end
  end

  def test_each_line_paragraph
    assert_in_out_err(['-e', 'ARGF.each_line("") {|para| p para}'], "a\n\nb\n",
                      ["\"a\\n\\n\"", "\"b\\n\""], [])
  end

  def test_each_line_chomp
    assert_in_out_err(['-e', 'ARGF.each_line(chomp: false) {|para| p para}'], "a\nb\n",
                      ["\"a\\n\"", "\"b\\n\""], [])
    assert_in_out_err(['-e', 'ARGF.each_line(chomp: true) {|para| p para}'], "a\nb\n",
                      ["\"a\"", "\"b\""], [])

    t = make_tempfile
    argf = ARGF.class.new(t.path)
    lines = []
    begin
      argf.each_line(chomp: true) do |line|
        lines << line
      end
    ensure
      argf.close
    end
    assert_equal(%w[foo bar baz], lines)
  end

  def test_each_byte
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        s = []
        ARGF.each_byte {|c| s << c }
        p s
      };
      assert_equal("[49, 10, 50, 10, 51, 10, 52, 10, 53, 10, 54, 10]\n", f.read)
    end
  end

  def test_each_char
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        s = ""
        ARGF.each_char {|c| s << c }
        puts s
      };
      assert_equal("1\n2\n3\n4\n5\n6\n", f.read)
    end
  end

  def test_filename
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        begin
          puts ARGF.filename.dump
        end while ARGF.gets
        puts ARGF.filename.dump
      };
      a = f.read.split("\n")
      assert_equal(@t1.path.dump, a.shift)
      assert_equal(@t1.path.dump, a.shift)
      assert_equal(@t1.path.dump, a.shift)
      assert_equal(@t2.path.dump, a.shift)
      assert_equal(@t2.path.dump, a.shift)
      assert_equal(@t3.path.dump, a.shift)
      assert_equal(@t3.path.dump, a.shift)
      assert_equal(@t3.path.dump, a.shift)
    end
  end

  def test_filename2
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        begin
          puts $FILENAME.dump
        end while ARGF.gets
        puts $FILENAME.dump
      };
      a = f.read.split("\n")
      assert_equal(@t1.path.dump, a.shift)
      assert_equal(@t1.path.dump, a.shift)
      assert_equal(@t1.path.dump, a.shift)
      assert_equal(@t2.path.dump, a.shift)
      assert_equal(@t2.path.dump, a.shift)
      assert_equal(@t3.path.dump, a.shift)
      assert_equal(@t3.path.dump, a.shift)
      assert_equal(@t3.path.dump, a.shift)
    end
  end

  def test_file
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        begin
          puts ARGF.file.path.dump
        end while ARGF.gets
        puts ARGF.file.path.dump
      };
      a = f.read.split("\n")
      assert_equal(@t1.path.dump, a.shift)
      assert_equal(@t1.path.dump, a.shift)
      assert_equal(@t1.path.dump, a.shift)
      assert_equal(@t2.path.dump, a.shift)
      assert_equal(@t2.path.dump, a.shift)
      assert_equal(@t3.path.dump, a.shift)
      assert_equal(@t3.path.dump, a.shift)
      assert_equal(@t3.path.dump, a.shift)
    end
  end

  def test_binmode
    bug5268 = '[ruby-core:39234]'
    open(@t3.path, "wb") {|f| f.write "5\r\n6\r\n"}
    ruby('-e', "ARGF.binmode; STDOUT.binmode; puts ARGF.read", @t1.path, @t2.path, @t3.path) do |f|
      f.binmode
      assert_equal("1\n2\n3\n4\n5\r\n6\r\n", f.read, bug5268)
    end
  end

  def test_textmode
    bug5268 = '[ruby-core:39234]'
    open(@t3.path, "wb") {|f| f.write "5\r\n6\r\n"}
    ruby('-e', "STDOUT.binmode; puts ARGF.read", @t1.path, @t2.path, @t3.path) do |f|
      f.binmode
      assert_equal("1\n2\n3\n4\n5\n6\n", f.read, bug5268)
    end
  end unless IO::BINARY.zero?

  def test_skip
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        ARGF.skip
        puts ARGF.gets
        ARGF.skip
        puts ARGF.read
      };
      assert_equal("1\n3\n4\n5\n6\n", f.read)
    end
  end

  def test_skip_in_each_line
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        ARGF.each_line {|l| print l; ARGF.skip}
      };
      assert_equal("1\n3\n5\n", f.read, '[ruby-list:49185]')
    end
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        ARGF.each_line {|l| ARGF.skip; puts [l, ARGF.gets].map {|s| s ? s.chomp : s.inspect}.join("+")}
      };
      assert_equal("1+3\n4+5\n6+nil\n", f.read, '[ruby-list:49185]')
    end
  end

  def test_skip_in_each_byte
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        ARGF.each_byte {|l| print l; ARGF.skip}
      };
      assert_equal("135".unpack("C*").join(""), f.read, '[ruby-list:49185]')
    end
  end

  def test_skip_in_each_char
    [[@t1, "\u{3042}"], [@t2, "\u{3044}"], [@t3, "\u{3046}"]].each do |f, s|
      File.write(f.path, s, mode: "w:utf-8")
    end
    ruby('-Eutf-8', '-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        ARGF.each_char {|l| print l; ARGF.skip}
      };
      assert_equal("\u{3042 3044 3046}", f.read, '[ruby-list:49185]')
    end
  end

  def test_skip_in_each_codepoint
    [[@t1, "\u{3042}"], [@t2, "\u{3044}"], [@t3, "\u{3046}"]].each do |f, s|
      File.write(f.path, s, mode: "w:utf-8")
    end
    ruby('-Eutf-8', '-Eutf-8', '-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        ARGF.each_codepoint {|l| printf "%x:", l; ARGF.skip}
      };
      assert_equal("3042:3044:3046:", f.read, '[ruby-list:49185]')
    end
  end

  def test_close
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        ARGF.close
        puts ARGF.read
      };
      assert_equal("3\n4\n5\n6\n", f.read)
    end
  end

  def test_close_replace
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}") do |f|
      paths = ['#{@t1.path}', '#{@t2.path}', '#{@t3.path}']
      {#
        ARGF.close
        ARGV.replace paths
        puts ARGF.read
      };
      assert_equal("1\n2\n3\n4\n5\n6\n", f.read)
    end
  end

  def test_closed
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        3.times do
          p ARGF.closed?
          ARGF.gets
          ARGF.gets
        end
        p ARGF.closed?
        ARGF.gets
        p ARGF.closed?
      };
      assert_equal("false\nfalse\nfalse\nfalse\ntrue\n", f.read)
    end
  end

  def test_argv
    ruby('-e', "p ARGF.argv; p $*", @t1.path, @t2.path, @t3.path) do |f|
      assert_equal([@t1.path, @t2.path, @t3.path].inspect, f.gets.chomp)
      assert_equal([@t1.path, @t2.path, @t3.path].inspect, f.gets.chomp)
    end
  end

  def test_readlines_limit_0
    bug4024 = '[ruby-dev:42538]'
    t = make_tempfile
    argf = ARGF.class.new(t.path)
    begin
      assert_raise(ArgumentError, bug4024) do
        argf.readlines(0)
      end
    ensure
      argf.close
    end
  end

  def test_each_line_limit_0
    bug4024 = '[ruby-dev:42538]'
    t = make_tempfile
    argf = ARGF.class.new(t.path)
    begin
      assert_raise(ArgumentError, bug4024) do
        argf.each_line(0).next
      end
    ensure
      argf.close
    end
  end

  def test_unreadable
    bug4274 = '[ruby-core:34446]'
    paths = (1..2).map do
      t = Tempfile.new("bug4274-")
      path = t.path
      t.close!
      path
    end
    argf = ARGF.class.new(*paths)
    paths.each do |path|
      assert_raise_with_message(Errno::ENOENT, /- #{Regexp.quote(path)}\z/) {argf.gets}
    end
    assert_nil(argf.gets, bug4274)
  end

  def test_readlines_chomp
    t = make_tempfile
    argf = ARGF.class.new(t.path)
    begin
      assert_equal(%w[foo bar baz], argf.readlines(chomp: true))
    ensure
      argf.close
    end

    assert_in_out_err(['-e', 'p readlines(chomp: true)'], "a\nb\n",
                      ["[\"a\", \"b\"]"], [])
  end

  def test_readline_chomp
    t = make_tempfile
    argf = ARGF.class.new(t.path)
    begin
      assert_equal("foo", argf.readline(chomp: true))
    ensure
      argf.close
    end

    assert_in_out_err(['-e', 'p readline(chomp: true)'], "a\nb\n",
                      ["\"a\""], [])
  end

  def test_gets_chomp
    t = make_tempfile
    argf = ARGF.class.new(t.path)
    begin
      assert_equal("foo", argf.gets(chomp: true))
    ensure
      argf.close
    end

    assert_in_out_err(['-e', 'p gets(chomp: true)'], "a\nb\n",
                      ["\"a\""], [])
  end

  def test_readlines_twice
    bug5952 = '[ruby-dev:45160]'
    assert_ruby_status(["-e", "2.times {STDIN.tty?; readlines}"], "", bug5952)
  end

  def test_each_codepoint
    ruby('-W1', '-e', "#{<<~"{#"}\n#{<<~'};'}", @t1.path, @t2.path, @t3.path) do |f|
      {#
        print Marshal.dump(ARGF.each_codepoint.to_a)
      };
      assert_equal([49, 10, 50, 10, 51, 10, 52, 10, 53, 10, 54, 10], Marshal.load(f.read))
    end
  end

  def test_read_nonblock
    ruby('-e', "#{<<~"{#"}\n#{<<~'};'}") do |f|
      {#
        $stdout.sync = true
        :wait_readable == ARGF.read_nonblock(1, "", exception: false) or
          abort "did not return :wait_readable"

        begin
          ARGF.read_nonblock(1)
          abort 'fail to raise IO::WaitReadable'
        rescue IO::WaitReadable
        end
        puts 'starting select'

        IO.select([ARGF]) == [[ARGF], [], []] or
          abort 'did not awaken for readability (before byte)'

        buf = ''
        buf.object_id == ARGF.read_nonblock(1, buf).object_id or
          abort "read destination buffer failed"
        print buf

        IO.select([ARGF]) == [[ARGF], [], []] or
          abort 'did not awaken for readability (before EOF)'

        ARGF.read_nonblock(1, buf, exception: false) == nil or
          abort "EOF should return nil if exception: false"

        begin
          ARGF.read_nonblock(1, buf)
          abort 'fail to raise IO::WaitReadable'
        rescue EOFError
          puts 'done with eof'
        end
      };
      f.sync = true
      assert_equal "starting select\n", f.gets
      f.write('.') # wake up from IO.select
      assert_equal '.', f.read(1)
      f.close_write
      assert_equal "done with eof\n", f.gets
    end
  end

  def test_wrong_type
    assert_separately([], "#{<<~"{#"}\n#{<<~'};'}")
    {#
      bug11610 = '[ruby-core:71140] [Bug #11610]'
      ARGV[0] = nil
      assert_raise(TypeError, bug11610) {gets}
    };
  end

  def test_sized_read
    s = "a"
    [@t1, @t2, @t3].each { |t|
      File.binwrite(t.path, s)
      s = s.succ
    }

    ruby('-e', "print ARGF.read(3)", @t1.path, @t2.path, @t3.path) do |f|
      assert_equal("abc", f.read)
    end

    argf = ARGF.class.new(@t1.path, @t2.path, @t3.path)
    begin
      assert_equal("abc", argf.read(3))
    ensure
      argf.close
    end
  end
end
