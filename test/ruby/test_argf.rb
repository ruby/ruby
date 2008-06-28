require 'test/unit'
require 'timeout'
require 'tmpdir'
require 'tempfile'
require_relative 'envutil'

class TestArgf < Test::Unit::TestCase
  def setup
    @t1 = Tempfile.new("foo")
    @t1.binmode
    @t1.puts "1"
    @t1.puts "2"
    @t1.close
    @t2 = Tempfile.new("bar")
    @t2.binmode
    @t2.puts "3"
    @t2.puts "4"
    @t2.close
    @t3 = Tempfile.new("baz")
    @t3.binmode
    @t3.puts "5"
    @t3.puts "6"
    @t3.close
    @tmps = [@t1, @t2, @t3]
  end

  def teardown
    @tmps.each {|t|
      bak = t.path + ".bak"
      File.unlink bak if File.file? bak
    }
  end

  def make_tempfile
    t = Tempfile.new("foo")
    t.puts "foo"
    t.puts "bar"
    t.puts "baz"
    t.close
    @tmps << t
    t
  end

  def ruby(*args)
    args = ['-e', '$>.write($<.read)'] if args.empty?
    ruby = EnvUtil.rubybin
    f = IO.popen([ruby] + args, 'r+')
    yield(f)
  ensure
    f.close unless !f || f.closed?
  end

  def no_safe_rename
    /cygwin|mswin|mingw|bccwin/ =~ RUBY_PLATFORM
  end

  def test_argf
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      a = ARGF
      b = a.dup
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["1", 1, "1", 1]
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["2", 2, "2", 2]
      a.rewind
      b.rewind
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["1", 1, "1", 3]
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["2", 2, "2", 4]
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["3", 3, "3", 5]
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["4", 4, "4", 6]
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["5", 5, "5", 7]
      a.rewind
      b.rewind
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["5", 5, "5", 8]
      p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno] #=> ["6", 6, "6", 9]
    SRC
      a = f.read.split("\n")
      assert_equal('["1", 1, "1", 1]', a.shift)
      assert_equal('["2", 2, "2", 2]', a.shift)
      assert_equal('["1", 1, "1", 3]', a.shift)
      assert_equal('["2", 2, "2", 4]', a.shift)
      assert_equal('["3", 3, "3", 5]', a.shift)
      assert_equal('["4", 4, "4", 6]', a.shift)
      assert_equal('["5", 5, "5", 7]', a.shift)
      assert_equal('["5", 5, "5", 8]', a.shift)
      assert_equal('["6", 6, "6", 9]', a.shift)

      # is this test OK? [ruby-dev:34445]
    end
  end

  def test_lineno
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      a = ARGF
      a.gets; p $.  #=> 1
      a.gets; p $.  #=> 2
      a.gets; p $.  #=> 3
      a.rewind; p $.  #=> 3
      a.gets; p $.  #=> 3
      a.gets; p $.  #=> 4
      a.rewind; p $.  #=> 4
      a.gets; p $.  #=> 3
      a.lineno = 1000; p $.  #=> 1000
      a.gets; p $.  #=> 1001
      a.gets; p $.  #=> 1002
      $. = 2000
      a.gets; p $.  #=> 2001
      a.gets; p $.  #=> 2001
    SRC
      assert_equal("1,2,3,3,3,4,4,3,1000,1001,1002,2001,2001", f.read.chomp.gsub("\n", ","))
    end
  end

  def test_lineno2
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      a = ARGF.dup
      a.gets; p $.  #=> 1
      a.gets; p $.  #=> 2
      a.gets; p $.  #=> 1
      a.rewind; p $.  #=> 1
      a.gets; p $.  #=> 1
      a.gets; p $.  #=> 2
      a.gets; p $.  #=> 1
      a.lineno = 1000; p $.  #=> 1
      a.gets; p $.  #=> 2
      a.gets; p $.  #=> 2
      $. = 2000
      a.gets; p $.  #=> 2001
      a.gets; p $.  #=> 2000
    SRC
      assert_equal("1,2,1,1,1,2,1,1,2,2,2000,2000", f.read.chomp.gsub("\n", ","))
    end
  end

  def test_inplace
    EnvUtil.rubyexec("-", @t1.path, @t2.path, @t3.path) do |w, r, e|
      w.puts "ARGF.inplace_mode = '.bak'"
      w.puts "while line = ARGF.gets"
      w.puts "  puts line.chomp + '.new'"
      w.puts "end"
      w.close
      assert_equal("", e.read)
      assert_equal("", r.read)
      assert_equal("1.new\n2.new\n", File.read(@t1.path))
      assert_equal("3.new\n4.new\n", File.read(@t2.path))
      assert_equal("5.new\n6.new\n", File.read(@t3.path))
      assert_equal("1\n2\n", File.read(@t1.path + ".bak"))
      assert_equal("3\n4\n", File.read(@t2.path + ".bak"))
      assert_equal("5\n6\n", File.read(@t3.path + ".bak"))
    end
  end

  def test_inplace2
    EnvUtil.rubyexec("-", @t1.path, @t2.path, @t3.path) do |w, r, e|
      w.puts "ARGF.inplace_mode = '.bak'"
      w.puts "puts ARGF.gets.chomp + '.new'"
      w.puts "puts ARGF.gets.chomp + '.new'"
      w.puts "p ARGF.inplace_mode"
      w.puts "ARGF.inplace_mode = nil"
      w.puts "puts ARGF.gets.chomp + '.new'"
      w.puts "puts ARGF.gets.chomp + '.new'"
      w.puts "p ARGF.inplace_mode"
      w.puts "ARGF.inplace_mode = '.bak'"
      w.puts "puts ARGF.gets.chomp + '.new'"
      w.puts "p ARGF.inplace_mode"
      w.puts "ARGF.inplace_mode = nil"
      w.puts "puts ARGF.gets.chomp + '.new'"
      w.close
      assert_equal("", e.read)
      assert_equal("", r.read)
      assert_equal("1.new\n2.new\n\".bak\"\n3.new\n4.new\nnil\n", File.read(@t1.path))
      assert_equal("3\n4\n", File.read(@t2.path))
      assert_equal("5.new\n\".bak\"\n6.new\n", File.read(@t3.path))
      assert_equal("1\n2\n", File.read(@t1.path + ".bak"))
      assert_equal(false, File.file?(@t2.path + ".bak"))
      assert_equal("5\n6\n", File.read(@t3.path + ".bak"))
    end
  end

  def test_inplace3
    EnvUtil.rubyexec("-i.bak", "-", @t1.path, @t2.path, @t3.path) do |w, r, e|
      w.puts "puts ARGF.gets.chomp + '.new'"
      w.puts "puts ARGF.gets.chomp + '.new'"
      w.puts "p $-i"
      w.puts "$-i = nil"
      w.puts "puts ARGF.gets.chomp + '.new'"
      w.puts "puts ARGF.gets.chomp + '.new'"
      w.puts "p $-i"
      w.puts "$-i = '.bak'"
      w.puts "puts ARGF.gets.chomp + '.new'"
      w.puts "p $-i"
      w.puts "$-i = nil"
      w.puts "puts ARGF.gets.chomp + '.new'"
      w.close
      assert_equal("", e.read)
      assert_equal("", r.read)
      assert_equal("1.new\n2.new\n\".bak\"\n3.new\n4.new\nnil\n", File.read(@t1.path))
      assert_equal("3\n4\n", File.read(@t2.path))
      assert_equal("5.new\n\".bak\"\n6.new\n", File.read(@t3.path))
      assert_equal("1\n2\n", File.read(@t1.path + ".bak"))
      assert_equal(false, File.file?(@t2.path + ".bak"))
      assert_equal("5\n6\n", File.read(@t3.path + ".bak"))
    end
  end

  def test_inplace_rename_impossible
    t = make_tempfile

    EnvUtil.rubyexec("-", t.path) do |w, r, e|
      w.puts "ARGF.inplace_mode = '/\\\\'"
      w.puts "while line = ARGF.gets"
      w.puts "  puts line.chomp + '.new'"
      w.puts "end"
      w.close
      if no_safe_rename
        assert_equal("", e.read)
        assert_equal("", r.read)
        assert_equal("foo.new\nbar.new\nbaz.new\n", File.read(t.path))
      else
        assert_match(/Can't rename .* to .*: .*. skipping file/, e.read) #'
        assert_equal("", r.read)
        assert_equal("foo\nbar\nbaz\n", File.read(t.path))
      end
    end
  end

  def test_inplace_no_backup
    t = make_tempfile

    EnvUtil.rubyexec("-", t.path) do |w, r, e|
      w.puts "ARGF.inplace_mode = ''"
      w.puts "while line = ARGF.gets"
      w.puts "  puts line.chomp + '.new'"
      w.puts "end"
      w.close
      if no_safe_rename
        assert_match(/Can't do inplace edit without backup/, e.read) #'
      else
        assert_equal("", e.read)
        assert_equal("", r.read)
        assert_equal("foo.new\nbar.new\nbaz.new\n", File.read(t.path))
      end
    end
  end

  def test_inplace_dup
    t = make_tempfile

    EnvUtil.rubyexec("-", t.path) do |w, r, e|
      w.puts "ARGF.inplace_mode = '.bak'"
      w.puts "f = ARGF.dup"
      w.puts "while line = f.gets"
      w.puts "  puts line.chomp + '.new'"
      w.puts "end"
      w.close
      assert_equal("", e.read)
      assert_equal("", r.read)
      assert_equal("foo.new\nbar.new\nbaz.new\n", File.read(t.path))
    end
  end

  def test_inplace_stdin
    t = make_tempfile

    EnvUtil.rubyexec("-", "-") do |w, r, e|
      w.puts "ARGF.inplace_mode = '.bak'"
      w.puts "f = ARGF.dup"
      w.puts "while line = f.gets"
      w.puts "  puts line.chomp + '.new'"
      w.puts "end"
      w.close
      assert_match("Can't do inplace edit for stdio; skipping", e.read)
      assert_equal("", r.read)
    end
  end

  def test_inplace_stdin2
    t = make_tempfile

    EnvUtil.rubyexec("-") do |w, r, e|
      w.puts "ARGF.inplace_mode = '.bak'"
      w.puts "while line = ARGF.gets"
      w.puts "  puts line.chomp + '.new'"
      w.puts "end"
      w.close
      assert_match("Can't do inplace edit for stdio", e.read)
      assert_equal("", r.read)
    end
  end

  def test_encoding
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      p ARGF.external_encoding.is_a?(Encoding)
      p ARGF.internal_encoding.is_a?(Encoding)
      ARGF.gets
      p ARGF.external_encoding.is_a?(Encoding)
      p ARGF.internal_encoding
    SRC
      assert_equal("true\ntrue\ntrue\nnil\n", f.read)
    end
  end

  def test_tell
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      begin
        ARGF.binmode
        loop do
          p ARGF.tell
          p ARGF.gets
        end
      rescue ArgumentError
        puts "end"
      end
    SRC
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
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      ARGF.seek(4)
      p ARGF.gets #=> "3"
      ARGF.seek(0, IO::SEEK_END)
      p ARGF.gets #=> "5"
      ARGF.seek(4)
      p ARGF.gets #=> nil
      begin
        ARGF.seek(0)
      rescue
        puts "end"
      end
    SRC
      a = f.read.split("\n")
      assert_equal('"3\n"', a.shift)
      assert_equal('"5\n"', a.shift)
      assert_equal('nil', a.shift)
      assert_equal('end', a.shift)
    end
  end

  def test_set_pos
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      ARGF.pos = 4
      p ARGF.gets #=> "3"
      ARGF.pos = 4
      p ARGF.gets #=> "5"
      ARGF.pos = 4
      p ARGF.gets #=> nil
      begin
        ARGF.pos = 4
      rescue
        puts "end"
      end
    SRC
      a = f.read.split("\n")
      assert_equal('"3\n"', a.shift)
      assert_equal('"5\n"', a.shift)
      assert_equal('nil', a.shift)
      assert_equal('end', a.shift)
    end
  end

  def test_rewind
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      ARGF.pos = 4
      ARGF.rewind
      p ARGF.gets #=> "1"
      ARGF.pos = 4
      p ARGF.gets #=> "3"
      ARGF.pos = 4
      p ARGF.gets #=> "5"
      ARGF.pos = 4
      p ARGF.gets #=> nil
      begin
        ARGF.rewind
      rescue
        puts "end"
      end
    SRC
      a = f.read.split("\n")
      assert_equal('"1\n"', a.shift)
      assert_equal('"3\n"', a.shift)
      assert_equal('"5\n"', a.shift)
      assert_equal('nil', a.shift)
      assert_equal('end', a.shift)
    end
  end

  def test_fileno
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
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
    SRC
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
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      8.times do
        p ARGF.to_io
        ARGF.gets
      end
    SRC
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
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      begin
        8.times do
          p ARGF.eof?
          ARGF.gets
        end
      rescue IOError
        puts "end"
      end
    SRC
      a = f.read.split("\n")
      ((%w(true false) * 4).take(7) + %w(end)).each do |x|
        assert_equal(x, a.shift)
      end
    end
  end

  def test_read
    ruby('-e', "p ARGF.read(8)", @t1.path, @t2.path, @t3.path) do |f|
      assert_equal("\"1\\n2\\n3\\n4\\n\"\n", f.read)
    end
  end

  def test_read2
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      s = ""
      ARGF.read(8, s)
      p s
    SRC
      assert_equal("\"1\\n2\\n3\\n4\\n\"\n", f.read)
    end
  end

  def test_read3
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      nil while ARGF.gets
      p ARGF.read
      p ARGF.read(0, "")
    SRC
      assert_equal("nil\n\"\"\n", f.read)
    end
  end

  def test_readpartial
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      s = ""
      begin
        loop do
          s << ARGF.readpartial(1)
          t = ""; ARGF.readpartial(1, t); s << t
        end
      rescue EOFError
        puts s
      end
    SRC
      assert_equal("1\n2\n3\n4\n5\n6\n", f.read)
    end
  end

  def test_readpartial2
    ruby('-e', <<-SRC) do |f|
      s = ""
      begin
        loop do
          s << ARGF.readpartial(1)
          t = ""; ARGF.readpartial(1, t); s << t
        end
      rescue EOFError
        puts s
      end
    SRC
      f.puts("foo")
      f.puts("bar")
      f.puts("baz")
      f.close_write
      assert_equal("foo\nbar\nbaz\n", f.read)
    end
  end

  def test_getc
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      s = ""
      while c = ARGF.getc
        s << c
      end
      puts s
    SRC
      assert_equal("1\n2\n3\n4\n5\n6\n", f.read)
    end
  end

  def test_getbyte
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      s = []
      while c = ARGF.getbyte
        s << c
      end
      p s
    SRC
      assert_equal("[49, 10, 50, 10, 51, 10, 52, 10, 53, 10, 54, 10]\n", f.read)
    end
  end

  def test_readchar
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      s = ""
      begin
        while c = ARGF.readchar
          s << c
        end
      rescue EOFError
        puts s
      end
    SRC
      assert_equal("1\n2\n3\n4\n5\n6\n", f.read)
    end
  end

  def test_readbyte
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      begin
        s = []
        while c = ARGF.readbyte
          s << c
        end
      rescue EOFError
        p s
      end
    SRC
      assert_equal("[49, 10, 50, 10, 51, 10, 52, 10, 53, 10, 54, 10]\n", f.read)
    end
  end

  def test_each_line
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      s = []
      ARGF.each_line {|l| s << l }
      p s
    SRC
      assert_equal("[\"1\\n\", \"2\\n\", \"3\\n\", \"4\\n\", \"5\\n\", \"6\\n\"]\n", f.read)
    end
  end

  def test_each_line_paragraph
    EnvUtil.rubyexec('-e', 'ARGF.each_line("") {|para| p para}') do |w, r, e|
      w << "a\n\nb\n"
      w.close
      assert_equal("\"a\\n\\n\"\n", r.gets, "[ruby-dev:34958]")
      assert_equal("\"b\\n\"\n", r.gets)
      assert_equal(nil, r.gets)
    end
  end

  def test_each_byte
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      s = []
      ARGF.each_byte {|c| s << c }
      p s
    SRC
      assert_equal("[49, 10, 50, 10, 51, 10, 52, 10, 53, 10, 54, 10]\n", f.read)
    end
  end

  def test_each_char
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      s = ""
      ARGF.each_char {|c| s << c }
      puts s
    SRC
      assert_equal("1\n2\n3\n4\n5\n6\n", f.read)
    end
  end

  def test_filename
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      begin
        puts ARGF.filename.dump
      end while ARGF.gets
      puts ARGF.filename.dump
    SRC
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
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      begin
        puts $FILENAME.dump
      end while ARGF.gets
      puts $FILENAME.dump
    SRC
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
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      begin
        puts ARGF.file.path.dump
      end while ARGF.gets
      puts ARGF.file.path.dump
    SRC
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
    ruby('-e', "ARGF.binmode; STDOUT.binmode; puts ARGF.read", @t1.path, @t2.path, @t3.path) do |f|
      f.binmode
      assert_equal("1\n2\n3\n4\n5\n6\n", f.read)
    end
  end

  def test_skip
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      begin
        ARGF.skip
      rescue
        puts "cannot skip" # ???
      end
      puts ARGF.gets
      ARGF.skip
      puts ARGF.read
    SRC
      assert_equal("cannot skip\n1\n3\n4\n5\n6\n", f.read)
    end
  end

  def test_close
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      ARGF.close
      puts ARGF.read
    SRC
      assert_equal("3\n4\n5\n6\n", f.read)
    end
  end

  def test_closed
    ruby('-e', <<-SRC, @t1.path, @t2.path, @t3.path) do |f|
      3.times do
        p ARGF.closed?
        ARGF.gets
        ARGF.gets
      end
      p ARGF.closed?
      ARGF.gets
      p ARGF.closed?
    SRC
      assert_equal("false\nfalse\nfalse\nfalse\ntrue\n", f.read)
    end
  end

  def test_argv
    ruby('-e', "p ARGF.argv; p $*", @t1.path, @t2.path, @t3.path) do |f|
      assert_equal([@t1.path, @t2.path, @t3.path].inspect, f.gets.chomp)
      assert_equal([@t1.path, @t2.path, @t3.path].inspect, f.gets.chomp)
    end
  end
end
