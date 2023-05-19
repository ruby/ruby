# frozen_string_literal: true

require "mkmf"

if ENV["BUNDLE"]
  # In this version we want to bundle all of the C source files together into
  # the gem so that it can all be compiled together.

  # Concatenate all of the C source files together to allow the compiler to
  # optimize across all of the source files.
  File.binwrite("yarp.c", Dir[File.expand_path("src/**/*.c", __dir__)].map { |src| File.binread(src) }.join("\n"))

  # Tell Ruby where to find the headers for YARP, specify the C standard, and make
  # sure all symbols are hidden by default.
  $CFLAGS << " -I#{__dir__}/include -std=gnu99 -fvisibility=hidden"

  $objs = %w[extension.o yarp.o node.o pack.o]
else
  # In this version we want to use the system installed version of YARP.
  find_header("yarp.h", File.expand_path("../../include", __dir__))
  unless find_library("rubyparser", "yp_parser_init", File.expand_path("../../build", __dir__))
    raise "Please run make to build librubyparser"
  end
end

create_makefile("yarp/yarp")
