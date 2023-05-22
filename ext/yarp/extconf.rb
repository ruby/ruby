# frozen_string_literal: true

# To build with librubyparser (in this repo):
#
# Prerequisite: clean checkout
#
# $ rake templates # to generate templated files
# $ make # build librubyparser
# $ rake compile -- --with-system-yarp # link against librubyparser
#
# To build standalone (in this repo):
#
# Prerequisite: clean checkout
#
# $ rake compile
require "mkmf"

# Link against librubyparse if it's available
has_library = have_library "rubyparser"

# If someone requests the system yarp, then test for it
if with_config("system-yarp")
  find_header("yarp.h", File.expand_path("../../internal", __dir__))
#  find_header("yarp.h", File.expand_path("../../include", __dir__))

  unless find_library("rubyparser", "yp_parser_init", File.expand_path("../../build", __dir__))
    raise "Please run make to build librubyparser"
  end
end

# If this function is available either via librubyparser
# or via Ruby itself, then use that function
if have_func("yp_parser_init")
  unless has_library
    $INCFLAGS << " -I$(topdir) -I$(top_srcdir)"
    $VPATH << '$(topdir)' << '$(top_srcdir)' # for id.h.
  end
else
  # In this version we want to bundle all of the C source files together into
  # the gem so that it can all be compiled together.

  # Concatenate all of the C source files together to allow the compiler to
  # optimize across all of the source files.
  File.binwrite("yarp.c", Dir[File.expand_path("../../src/**/*.c", __dir__)].map { |src| File.binread(src) }.join("\n"))

  inc = File.expand_path("../../include", __dir__)
  # Tell Ruby where to find the headers for YARP, specify the C standard, and make
  # sure all symbols are hidden by default.
  $CFLAGS << " -I#{inc} -std=gnu99 -fvisibility=hidden"

  $objs = %w[compile.o extension.o yarp.o node.o pack.o]
end

create_makefile("yarp/yarp")
