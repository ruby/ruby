require 'test/unit'
require 'tmpdir'
require_relative 'envutil'

class TestDir_M17N < Test::Unit::TestCase
  def with_tmpdir
    Dir.mktmpdir {|dir|
      Dir.chdir(dir) {
        yield dir
      }
    }
  end

  def assert_raw_file_name(code, encoding)
    with_tmpdir { |dir|
      assert_separately(["-E#{encoding}"], <<-EOS, :chdir=>dir)
        filename = #{code}.chr('UTF-8').force_encoding("#{encoding}")
        File.open(filename, "w") {}
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        assert_include(ents, filename)
      EOS

      assert_separately(%w[-EASCII-8BIT], <<-EOS, :chdir=>dir)
        filename = #{code}.chr('UTF-8').force_encoding("ASCII-8BIT")
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        expected_filename = #{code}.chr('UTF-8').encode(Encoding.find("filesystem")) rescue expected_filename = "?"
        expected_filename = expected_filename.force_encoding("ASCII-8BIT")
        if /mswin|mingw/ =~ RUBY_PLATFORM
          case
          when ents.include?(filename)
          when ents.include?(expected_filename)
            filename = expected_filename
          else
            ents = Dir.entries(".", {:encoding => Encoding.find("filesystem")})
            filename = expected_filename
          end
        end
        assert_include(ents, filename)
      EOS
    }
  end

  ## UTF-8 default_external, no default_internal

  def test_filename_extutf8
    with_tmpdir {|d|
      assert_separately(%w[-EUTF-8], <<-'EOS', :chdir=>d)
        filename = "\u3042"
        File.open(filename, "w") {}
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        assert_include(ents, filename)
      EOS
    }
  end

  def test_filename_extutf8_invalid
    with_tmpdir {|d|
      assert_separately(%w[-EASCII-8BIT], <<-'EOS', :chdir=>d)
        filename = "\xff".force_encoding("ASCII-8BIT") # invalid byte sequence as UTF-8
        File.open(filename, "w") {}
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        filename = "%FF" if /darwin/ =~ RUBY_PLATFORM && ents.include?("%FF")
        assert_include(ents, filename)
      EOS
      assert_separately(%w[-EUTF-8], <<-'EOS', :chdir=>d)
        filename = "\xff".force_encoding("UTF-8") # invalid byte sequence as UTF-8
        File.open(filename, "w") {}
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        filename = "%FF" if /darwin/ =~ RUBY_PLATFORM && ents.include?("%FF")
        assert_include(ents, filename)
      EOS
    }
  end unless /mswin|mingw/ =~ RUBY_PLATFORM

  def test_filename_as_bytes_extutf8
    with_tmpdir {|d|
      assert_separately(%w[-EUTF-8], <<-'EOS', :chdir=>d)
        filename = "\xc2\xa1".force_encoding("utf-8")
        File.open(filename, "w") {}
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        assert_include(ents, filename)
      EOS
      assert_separately(%w[-EUTF-8], <<-'EOS', :chdir=>d)
        if /mswin|mingw|darwin/ =~ RUBY_PLATFORM
          filename = "\x8f\xa2\xc2".force_encoding("euc-jp")
        else
          filename = "\xc2\xa1".force_encoding("euc-jp")
        end
        assert_nothing_raised(Errno::ENOENT) do
          open(filename) {}
        end
      EOS
      # no meaning test on windows
      unless /mswin|mingw|darwin/ =~ RUBY_PLATFORM
        assert_separately(%W[-EUTF-8], <<-'EOS', :chdir=>d)
          filename1 = "\xc2\xa1".force_encoding("utf-8")
          filename2 = "\xc2\xa1".force_encoding("euc-jp")
          filename3 = filename1.encode("euc-jp")
          filename4 = filename2.encode("utf-8")
          assert_file.stat(filename1)
          assert_file.stat(filename2)
          assert_file.not_exist?(filename3)
          assert_file.not_exist?(filename4)
        EOS
      end
    }
  end

  ## UTF-8 default_external, EUC-JP default_internal

  def test_filename_extutf8_inteucjp_representable
    with_tmpdir {|d|
      assert_separately(%w[-EUTF-8], <<-'EOS', :chdir=>d)
        filename = "\u3042"
        File.open(filename, "w") {}
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        assert_include(ents, filename)
      EOS
      assert_separately(%w[-EUTF-8:EUC-JP], <<-'EOS', :chdir=>d)
        filename = "\xA4\xA2".force_encoding("euc-jp")
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        assert_include(ents, filename)
      EOS
      assert_separately(%w[-EUTF-8:EUC-JP], <<-'EOS', :chdir=>d)
        filename = "\xA4\xA2".force_encoding("euc-jp")
        assert_nothing_raised(Errno::ENOENT) do
          open(filename) {}
        end
      EOS
    }
  end

  def test_filename_extutf8_inteucjp_unrepresentable
    with_tmpdir {|d|
      assert_separately(%w[-EUTF-8], <<-'EOS', :chdir=>d)
        filename1 = "\u2661" # WHITE HEART SUIT which is not representable in EUC-JP
        filename2 = "\u3042" # HIRAGANA LETTER A which is representable in EUC-JP
        File.open(filename1, "w") {}
        File.open(filename2, "w") {}
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        assert_include(ents, filename1)
        assert_include(ents, filename2)
      EOS
      assert_separately(%w[-EUTF-8:EUC-JP], <<-'EOS', :chdir=>d)
        filename1 = "\u2661" # WHITE HEART SUIT which is not representable in EUC-JP
        filename2 = "\xA4\xA2".force_encoding("euc-jp") # HIRAGANA LETTER A in EUC-JP
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        assert_include(ents, filename1)
        assert_include(ents, filename2)
      EOS
      assert_separately(%w[-EUTF-8:EUC-JP], <<-'EOS', :chdir=>d)
        filename1 = "\u2661" # WHITE HEART SUIT which is not representable in EUC-JP
        filename2 = "\u3042" # HIRAGANA LETTER A which is representable in EUC-JP
        filename3 = "\xA4\xA2".force_encoding("euc-jp") # HIRAGANA LETTER A in EUC-JP
        assert_file.stat(filename1)
        assert_file.stat(filename2)
        assert_file.stat(filename3)
      EOS
    }
  end

  ## others

  def test_filename_bytes_euc_jp
    with_tmpdir {|d|
      assert_separately(%w[-EEUC-JP], <<-'EOS', :chdir=>d)
        filename = "\xA4\xA2".force_encoding("euc-jp")
        File.open(filename, "w") {}
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        ents.each {|e| e.force_encoding("ASCII-8BIT") }
        if /darwin/ =~ RUBY_PLATFORM
          filename = filename.encode("utf-8")
        end
        assert_include(ents, filename.force_encoding("ASCII-8BIT"))
      EOS
    }
  end

  def test_filename_euc_jp
    with_tmpdir {|d|
      assert_separately(%w[-EEUC-JP], <<-'EOS', :chdir=>d)
        filename = "\xA4\xA2".force_encoding("euc-jp")
        File.open(filename, "w") {}
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        if /darwin/ =~ RUBY_PLATFORM
          filename = filename.encode("utf-8").force_encoding("euc-jp")
        end
        assert_include(ents, filename)
      EOS
      assert_separately(%w[-EASCII-8BIT], <<-'EOS', :chdir=>d)
        filename = "\xA4\xA2".force_encoding('ASCII-8BIT')
        win_expected_filename = filename.encode(Encoding.find("filesystem"), "euc-jp") rescue "?"
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        unless ents.include?(filename)
          case RUBY_PLATFORM
          when /darwin/
            filename = filename.encode("utf-8", "euc-jp").b
          when /mswin|mingw/
            if ents.include?(win_expected_filename.dup.force_encoding("ASCII-8BIT"))
              ents = Dir.entries(".", {:encoding => Encoding.find("filesystem")})
              filename = win_expected_filename
            end
          end
        end
        assert_include(ents, filename)
      EOS
    }
  end

  def test_filename_utf8_raw_jp_name
    assert_raw_file_name(0x3042, "UTF-8")
  end

  def test_filename_utf8_raw_windows_1251_name
    assert_raw_file_name(0x0424, "UTF-8")
  end

  def test_filename_utf8_raw_windows_1252_name
    assert_raw_file_name(0x00c6, "UTF-8")
  end

  def test_filename_ext_euc_jp_and_int_utf_8
    with_tmpdir {|d|
      assert_separately(%w[-EEUC-JP], <<-'EOS', :chdir=>d)
        filename = "\xA4\xA2".force_encoding("euc-jp")
        File.open(filename, "w") {}
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        if /darwin/ =~ RUBY_PLATFORM
          filename = filename.encode("utf-8", "euc-jp").force_encoding("euc-jp")
        end
        assert_include(ents, filename)
      EOS
      assert_separately(%w[-EEUC-JP:UTF-8], <<-'EOS', :chdir=>d)
        filename = "\u3042"
        opts = {:encoding => Encoding.default_external} if /mswin|mingw/ =~ RUBY_PLATFORM
        ents = Dir.entries(".", opts)
        if /darwin/ =~ RUBY_PLATFORM
          filename = filename.force_encoding("euc-jp")
        end
        assert_include(ents, filename)
      EOS
    }
  end

  def test_error_nonascii
    bug6071 = '[ruby-dev:45279]'
    paths = ["\u{3042}".encode("sjis"), "\u{ff}".encode("iso-8859-1")]
    encs = with_tmpdir {
      paths.map {|path|
        Dir.open(path) rescue $!.message.encoding
      }
    }
    assert_equal(paths.map(&:encoding), encs, bug6071)
  end

  def test_inspect_nonascii
    bug6072 = '[ruby-dev:45280]'
    paths = ["\u{3042}".encode("sjis"), "\u{ff}".encode("iso-8859-1")]
    encs = with_tmpdir {
      paths.map {|path|
        Dir.mkdir(path)
        Dir.open(path) {|d| d.inspect.encoding}
      }
    }
    assert_equal(paths.map(&:encoding), encs, bug6072)
  end

  def test_glob_incompatible
    d = "\u{3042}\u{3044}".encode("utf-16le")
    assert_raise(Encoding::CompatibilityError) {Dir.glob(d)}
    m = Class.new {define_method(:to_path) {d}}
    assert_raise(Encoding::CompatibilityError) {Dir.glob(m.new)}
  end

  def test_glob_compose
    bug7267 = '[ruby-core:48745] [Bug #7267]'

    pp = Object.new.extend(Test::Unit::Assertions)
    def pp.mu_pp(str) #:nodoc:
      str.dump
    end

    with_tmpdir {|d|
      orig = %W"d\u{e9}tente x\u{304c 304e 3050 3052 3054}"
      orig.each {|n| open(n, "w") {}}
      orig.each do |o|
        n = Dir.glob("#{o[0..0]}*")[0]
        pp.assert_equal(o, n, bug7267)
      end
    }
  end

  def test_entries_compose
    bug7267 = '[ruby-core:48745] [Bug #7267]'

    pp = Object.new.extend(Test::Unit::Assertions)
    def pp.mu_pp(ary) #:nodoc:
      '[' << ary.map {|str| "#{str.dump}(#{str.encoding})"}.join(', ') << ']'
    end

    with_tmpdir {|d|
      orig = %W"d\u{e9}tente x\u{304c 304e 3050 3052 3054}"
      orig.each {|n| open(n, "w") {}}
      if /mswin|mingw/ =~ RUBY_PLATFORM
        opts = {:encoding => Encoding.default_external}
        orig.map! {|o| o.encode(Encoding.find("filesystem")) rescue o.tr("^a-z", "?")}
      else
        enc = Encoding.find("filesystem")
        enc = Encoding::ASCII_8BIT if enc == Encoding::US_ASCII
        orig.each {|o| o.force_encoding(enc) }
      end
      ents = Dir.entries(".", opts).reject {|n| /\A\./ =~ n}
      ents.sort!
      pp.assert_equal(orig, ents, bug7267)
    }
  end
end
