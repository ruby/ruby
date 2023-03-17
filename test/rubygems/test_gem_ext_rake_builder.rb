# frozen_string_literal: true

require_relative "helper"
require "rubygems/ext"

class TestGemExtRakeBuilder < Gem::TestCase
  def setup
    super

    @ext = File.join @tempdir, "ext"
    @dest_path = File.join @tempdir, "prefix"

    FileUtils.mkdir_p @ext
    FileUtils.mkdir_p @dest_path
  end

  def test_class_build
    create_temp_mkrf_file("task :default")
    output = []

    build_rake_in do |rake|
      Gem::Ext::RakeBuilder.build "mkrf_conf.rb", @dest_path, output, [], nil, @ext

      output = output.join "\n"

      refute_match %r{^rake failed:}, output
      assert_match %r{^#{Regexp.escape Gem.ruby} mkrf_conf\.rb}, output
      assert_match %r{^#{Regexp.escape rake} RUBYARCHDIR\\=#{Regexp.escape @dest_path} RUBYLIBDIR\\=#{Regexp.escape @dest_path}}, output
    end
  end

  # https://github.com/rubygems/rubygems/pull/1819
  #
  # It should not fail with a non-empty args list either
  def test_class_build_with_args
    create_temp_mkrf_file("task :default")
    output = []

    build_rake_in do |rake|
      non_empty_args_list = [""]
      Gem::Ext::RakeBuilder.build "mkrf_conf.rb", @dest_path, output, non_empty_args_list, nil, @ext

      output = output.join "\n"

      refute_match %r{^rake failed:}, output
      assert_match %r{^#{Regexp.escape Gem.ruby} mkrf_conf\.rb}, output
      assert_match %r{^#{Regexp.escape rake} RUBYARCHDIR\\=#{Regexp.escape @dest_path} RUBYLIBDIR\\=#{Regexp.escape @dest_path}}, output
    end
  end

  def test_class_no_openssl_override
    pend "openssl is missing" unless Gem::HAVE_OPENSSL

    create_temp_mkrf_file("task :default")

    rake = util_spec "rake" do |s|
      s.executables = %w[rake]
      s.files = %w[bin/rake]
    end

    output = []

    write_file File.join(@tempdir, "bin", "rake") do |fp|
      fp.puts "#!/usr/bin/ruby"
      fp.puts "require 'openssl'; puts OpenSSL"
    end

    install_gem rake

    Gem::Ext::RakeBuilder.build "mkrf_conf.rb", @dest_path, output, [""], nil, @ext

    output = output.join "\n"

    assert_match "OpenSSL", output
    assert_match %r{^#{Regexp.escape Gem.ruby} mkrf_conf\.rb}, output
  end

  def test_class_build_no_mkrf_passes_args
    output = []

    build_rake_in do |rake|
      Gem::Ext::RakeBuilder.build "ext/Rakefile", @dest_path, output, ["test1", "test2"], nil, @ext

      output = output.join "\n"

      refute_match %r{^rake failed:}, output
      assert_match %r{^#{Regexp.escape rake} RUBYARCHDIR\\=#{Regexp.escape @dest_path} RUBYLIBDIR\\=#{Regexp.escape @dest_path} test1 test2}, output
    end
  end

  def test_class_build_fail
    create_temp_mkrf_file("task :default do abort 'fail' end")
    output = []

    build_rake_in(false) do |_rake|
      error = assert_raise Gem::InstallError do
        Gem::Ext::RakeBuilder.build "mkrf_conf.rb", @dest_path, output, [], nil, @ext
      end

      assert_match %r{^rake failed}, error.message
    end
  end

  def create_temp_mkrf_file(rakefile_content)
    File.open File.join(@ext, "mkrf_conf.rb"), "w" do |mkrf_conf|
      mkrf_conf.puts <<-EO_MKRF
        File.open("Rakefile","w") do |f|
          f.puts "#{rakefile_content}"
        end
      EO_MKRF
    end
  end
end
