# frozen_string_literal: true

require "yarp_test_helper"

if RUBY_PLATFORM =~ /linux/
  #
  #  examine a yarp dll or static archive for expected external symbols.
  #  these tests only work on a linux system right now.
  #
  class LibrarySymbolsTest < Test::Unit::TestCase
    def setup
      super

      @librubyparser_a = File.expand_path(File.join(__dir__, "..", "build", "librubyparser.a"))
      @librubyparser_so = File.expand_path(File.join(__dir__, "..", "build", "librubyparser.so"))
      @yarp_so = File.expand_path(File.join(__dir__, "..", "lib", "yarp", "yarp.so"))
    end

    # objdump runner and helpers
    def objdump(path)
      assert_path_exist(path)
      %x(objdump --section=.text --syms #{path}).split("\n")
    end

    def global_objdump_symbols(path)
      objdump(path).select { |line| line[17] == "g" }
    end

    def hidden_global_objdump_symbols(path)
      global_objdump_symbols(path).select { |line| line =~ / \.hidden / }
    end

    def visible_global_objdump_symbols(path)
      global_objdump_symbols(path).reject { |line| line =~ / \.hidden / }
    end

    # nm runner and helpers
    def nm(path)
      assert_path_exist(path)
      %x(nm #{path}).split("\n")
    end

    def global_nm_symbols(path)
      nm(path).select { |line| line[17] == "T" }
    end

    def local_nm_symbols(path)
      nm(path).select { |line| line[17] == "t" }
    end

    # dig the symbol name out of each line. works for both `objdump` and `nm` output.
    def names(symbol_lines)
      symbol_lines.map { |line| line.split(/\s+/).last }
    end

    #
    #  static archive - librubyparser.a
    #
    def test_librubyparser_a_contains_nothing_globally_visible
      omit("librubyparser.a is not built") unless File.exist?(@librubyparser_a)

      assert_empty(names(visible_global_objdump_symbols(@librubyparser_a)))
    end

    def test_librubyparser_a_contains_hidden_yp_symbols
      omit("librubyparser.a is not built") unless File.exist?(@librubyparser_a)

      names(hidden_global_objdump_symbols(@librubyparser_a)).tap do |symbols|
        assert_includes(symbols, "yp_parse")
        assert_includes(symbols, "yp_version")
      end
    end

    #
    #  shared object - librubyparser.so
    #
    def test_librubyparser_so_exports_only_the_necessary_functions
      omit("librubyparser.so is not built") unless File.exist?(@librubyparser_so)

      names(global_nm_symbols(@librubyparser_so)).tap do |symbols|
        assert_includes(symbols, "yp_parse")
        assert_includes(symbols, "yp_version")
      end
      names(local_nm_symbols(@librubyparser_so)).tap do |symbols|
        assert_includes(symbols, "yp_encoding_shift_jis_isupper_char")
      end
      # TODO: someone who uses this library needs to finish this test
    end

    #
    #  shared object - yarp.so
    #
    def test_yarp_so_exports_only_the_C_extension_init_function
      omit("yarp.so is not built") unless File.exist?(@yarp_so)

      names(global_nm_symbols(@yarp_so)).tap do |symbols|
        assert_equal(["Init_yarp"], symbols)
      end
    end
  end
end
