# frozen_string_literal: true

require_relative 'base'

class TestMkmfMakefile < TestMkmf
  def test_echo_command
    create_makefile("test")

    assert_include File.read("Makefile"), "ECHO = $(ECHO1:0=@ #{$nmake ? "echo" : "/bin/echo"})"
  end

  def test_echo_does_not_resolve_from_path
    omit "POSIX Makefile only" if $nmake

    Dir.mkdir("fake-bin")
    File.write("fake-bin/echo", <<~SH)
      #!/bin/sh
      touch path-echo-used
      exit 77
    SH
    File.chmod(0o755, "fake-bin/echo")

    env = {"PATH" => [File.expand_path("fake-bin"), ENV.fetch("PATH")].join(File::PATH_SEPARATOR)}

    create_makefile("test")

    File.open("Makefile", "a") do |f|
      f.puts
      f.puts "test-echo:"
      f.puts "\t$(ECHO) testing"
    end

    assert(system(env, ENV["MAKE"] || RbConfig::CONFIG["MAKE"] || "make", "test-echo"))
    assert_not_predicate(Pathname("path-echo-used"), :exist?)
  end
end
