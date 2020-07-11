# frozen_string_literal: true

require "rbconfig"
require "fileutils"

archdir = RbConfig::CONFIG["archdir"]
rubylibdir = RbConfig::CONFIG["rubylibdir"]
default_specifications_dir = Gem.default_specifications_dir

openssl_rb = File.join(rubylibdir, "openssl.rb")
openssl_gemspec = Dir.glob("#{default_specifications_dir}/openssl-*.gemspec").first

openssl_ext = if RUBY_PLATFORM == "java"
                File.join(rubylibdir, "jopenssl.jar")
              else
                File.join(archdir, "openssl.so")
              end

FileUtils.mv openssl_rb, openssl_rb + "_"
FileUtils.mv openssl_ext, openssl_ext + "_"
FileUtils.mv openssl_gemspec, openssl_gemspec + "_" if openssl_gemspec
