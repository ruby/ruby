require_relative 'base'
require 'tempfile'

class TestMkmf
  class TestHaveLibrary < TestMkmf
    LIBRARY_NAME = 'mkmftest'
    HEADER_NAME = "#{LIBRARY_NAME}.h"
    FUNC_NAME = 'ruby_mkmftest_foo'
    ARPREFIX = config_string('LIBRUBY_A') {|lib| lib[/\A\w+/]}

    def create_library(libname = LIBRARY_NAME)
      lib = "#{ARPREFIX}#{libname}.#{$LIBEXT}"
      open(HEADER_NAME, "w") do |hdr|
        hdr.puts "void #{FUNC_NAME}(void);"
        hdr.puts "void #{FUNC_NAME}_fake(void);"
      end
      create_tmpsrc("#include \"#{HEADER_NAME}\"\n""void #{FUNC_NAME}(void) {}")
      assert(xsystem(cc_command), "compile failed: #{cc_command}")
      command = "#{CONFIG['AR']} #{config_string('ARFLAGS') || 'cru '}#{lib} #{CONFTEST}.#{$OBJEXT}"
      assert(xsystem(command), "making library failed: #{command}")
      File.unlink("#{CONFTEST}.#{$OBJEXT}")
      config_string('RANLIB') do |ranlib|
        command = "#{ranlib} #{lib}"
        assert(xsystem(command), "ranlib failed: #{command}")
      end
    end

    def assert_have_library(*args)
      assert_equal(true, have_library(LIBRARY_NAME, *args), MKMFLOG)
    end

    def assert_not_have_library(*args)
      assert_equal(false, have_library(LIBRARY_NAME, *args), MKMFLOG)
    end

    def test_have_library
      create_library
      assert_have_library
    end

    def test_have_library_with_name
      create_library
      assert_have_library(FUNC_NAME, HEADER_NAME)
    end

    def test_not_have_library
      assert_not_have_library
    end

    def test_not_have_library_with_name
      create_library
      assert_not_have_library("#{FUNC_NAME}_fake", HEADER_NAME)
    end
  end
end
