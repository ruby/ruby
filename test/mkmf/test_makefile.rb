# frozen_string_literal: false

require_relative 'base'
require 'open3'

class TestMkmfMakefile < TestMkmf
  def test_echo_does_not_resolve_from_path
    omit "POSIX Makefile only" if $nmake

    fake_bin = File.join(@tmpdir, "fake-bin")
    marker = File.join(@tmpdir, "fake-echo-invoked")
    fake_echo = File.join(fake_bin, "echo")

    FileUtils.mkdir_p(fake_bin)
    File.write(fake_echo, <<~SH)
      #!/bin/sh
      printf '%s\n' invoked > #{marker.dump}
      exit 77
    SH
    FileUtils.chmod(0o755, fake_echo)

    mkmf do
      create_makefile("test")
    end

    File.open("Makefile", "a") do |makefile|
      makefile.puts <<~MAKE

        test-echo:
        \t$(ECHO) testing
      MAKE
    end

    env = {"PATH" => [fake_bin, ENV["PATH"]].compact.join(File::PATH_SEPARATOR)}
    make = ENV.fetch("MAKE", "make")
    output, status = Open3.capture2e(env, make, "test-echo")

    assert_predicate(status, :success?, output)
    assert_not_path_exist(marker)
  end
end