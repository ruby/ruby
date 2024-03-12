# frozen_string_literal: true

require_relative "test_helper"

return if RUBY_PLATFORM !~ /linux/

# TODO: determine why these symbols are incorrect on ppc64le
return if RUBY_PLATFORM =~ /powerpc64le/

module Prism
  #
  #  examine a prism dll or static archive for expected external symbols.
  #  these tests only work on a linux system right now.
  #
  class LibrarySymbolsTest < TestCase
    def setup
      super

      @libprism_a = File.expand_path("../../build/libprism.a", __dir__)
      @libprism_so = File.expand_path("../../build/libprism.so", __dir__)
      @prism_so = File.expand_path("../../lib/prism/prism.so", __dir__)
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
    #  static archive - libprism.a
    #
    def test_libprism_a_contains_nothing_globally_visible
      omit("libprism.a is not built") unless File.exist?(@libprism_a)

      assert_empty(names(visible_global_objdump_symbols(@libprism_a)))
    end

    def test_libprism_a_contains_hidden_pm_symbols
      omit("libprism.a is not built") unless File.exist?(@libprism_a)

      names(hidden_global_objdump_symbols(@libprism_a)).tap do |symbols|
        assert_includes(symbols, "pm_parse")
        assert_includes(symbols, "pm_version")
      end
    end

    #
    #  shared object - libprism.so
    #
    def test_libprism_so_exports_only_the_necessary_functions
      omit("libprism.so is not built") unless File.exist?(@libprism_so)

      names(global_nm_symbols(@libprism_so)).tap do |symbols|
        assert_includes(symbols, "pm_parse")
        assert_includes(symbols, "pm_version")
      end
      names(local_nm_symbols(@libprism_so)).tap do |symbols|
        assert_includes(symbols, "pm_encoding_utf_8_isupper_char")
      end
      # TODO: someone who uses this library needs to finish this test
    end

    #
    #  shared object - prism.so
    #
    def test_prism_so_exports_only_the_C_extension_init_function
      omit("prism.so is not built") unless File.exist?(@prism_so)

      names(global_nm_symbols(@prism_so)).tap do |symbols|
        assert_equal(["Init_prism"], symbols)
      end
    end
  end
end
