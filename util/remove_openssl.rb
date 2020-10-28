# frozen_string_literal: true

require "rbconfig"
require "fileutils"

class OpensslSimulator
  attr_reader :openssl_rb, :openssl_gemspec, :openssl_ext

  def initialize
    archdir = RbConfig::CONFIG["archdir"]
    rubylibdir = RbConfig::CONFIG["rubylibdir"]
    default_specifications_dir = Gem.default_specifications_dir

    @openssl_rb = File.join(rubylibdir, "openssl.rb")
    @openssl_gemspec = Dir.glob("#{default_specifications_dir}/openssl-*.gemspec").first

    @openssl_ext = if RUBY_PLATFORM == "java"
                     File.join(rubylibdir, "jopenssl.jar")
                   else
                     File.join(archdir, "openssl.so")
                   end
  end

  def hide_openssl
    hide_file openssl_rb
    hide_file openssl_ext
    hide_file openssl_gemspec if openssl_gemspec
  end

  def unhide_openssl
    unhide_file openssl_gemspec if openssl_gemspec
    unhide_file openssl_ext
    unhide_file openssl_rb
  end

  private

  def hide_file(file)
    FileUtils.mv file, file + "_"
  end

  def unhide_file(file)
    FileUtils.mv file + "_", file
  end
end

if $0 == __FILE__
  openssl_simulate = OpensslSimulator.new

  if ARGV[0] == "--revert"
    openssl_simulate.unhide_openssl
  else
    openssl_simulate.hide_openssl
  end
end
