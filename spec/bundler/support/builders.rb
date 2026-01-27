# frozen_string_literal: true

require "bundler/shared_helpers"
require "shellwords"
require "fileutils"
require "rubygems/package"

require_relative "build_metadata"

module Spec
  module Builders
    def self.extended(mod)
      mod.extend Path
      mod.extend Helpers
    end

    def self.constantize(name)
      name.delete("-").upcase
    end

    def v(version)
      Gem::Version.new(version)
    end

    def pl(platform)
      Gem::Platform.new(platform)
    end

    def build_repo1
      build_repo gem_repo1 do
        FileUtils.cp rake_path, "#{gem_repo1}/gems/"

        build_gem "coffee-script-source"
        build_gem "git"
        build_gem "puma"
        build_gem "minitest"

        build_gem "myrack", %w[0.9.1 1.0.0] do |s|
          s.executables = "myrackup"
          s.post_install_message = "Myrack's post install message"
        end

        build_gem "thin" do |s|
          s.add_dependency "myrack"
          s.post_install_message = "Thin's post install message"
        end

        build_gem "myrack-obama" do |s|
          s.add_dependency "myrack"
          s.post_install_message = "Myrack-obama's post install message"
        end

        build_gem "myrack_middleware", "1.0" do |s|
          s.add_dependency "myrack", "0.9.1"
        end

        build_gem "rails", "2.3.2" do |s|
          s.executables = "rails"
          s.add_dependency "rake",           rake_version
          s.add_dependency "actionpack",     "2.3.2"
          s.add_dependency "activerecord",   "2.3.2"
          s.add_dependency "actionmailer",   "2.3.2"
          s.add_dependency "activeresource", "2.3.2"
        end
        build_gem "actionpack", "2.3.2" do |s|
          s.add_dependency "activesupport", "2.3.2"
        end
        build_gem "activerecord", ["2.3.1", "2.3.2"] do |s|
          s.add_dependency "activesupport", "2.3.2"
        end
        build_gem "actionmailer", "2.3.2" do |s|
          s.add_dependency "activesupport", "2.3.2"
        end
        build_gem "activeresource", "2.3.2" do |s|
          s.add_dependency "activesupport", "2.3.2"
        end
        build_gem "activesupport", %w[1.2.3 2.3.2 2.3.5]

        build_gem "activemerchant" do |s|
          s.add_dependency "activesupport", ">= 2.0.0"
        end

        build_gem "rspec", "1.2.7", no_default: true do |s|
          s.write "lib/spec.rb", "SPEC = '1.2.7'"
        end

        build_gem "myrack-test", no_default: true do |s|
          s.write "lib/myrack/test.rb", "MYRACK_TEST = '1.0'"
        end

        build_gem "platform_specific" do |s|
          s.platform = "java"
        end

        build_gem "platform_specific" do |s|
          s.platform = "ruby"
        end

        build_gem "platform_specific" do |s|
          s.platform = "x86-mswin32"
        end

        build_gem "platform_specific" do |s|
          s.platform = "x64-mswin64"
        end

        build_gem "platform_specific" do |s|
          s.platform = "x86-mingw32"
        end

        build_gem "platform_specific" do |s|
          s.platform = "x64-mingw-ucrt"
        end

        build_gem "platform_specific" do |s|
          s.platform = "aarch64-mingw-ucrt"
        end

        build_gem "platform_specific" do |s|
          s.platform = "x86-darwin-100"
        end

        build_gem "only_java", "1.0" do |s|
          s.platform = "java"
        end

        build_gem "only_java", "1.1" do |s|
          s.platform = "java"
        end

        build_gem "nokogiri", "1.4.2"
        build_gem "nokogiri", "1.4.2" do |s|
          s.platform = "java"
          s.add_dependency "weakling", ">= 0.0.3"
        end

        build_gem "laduradura", "5.15.2"
        build_gem "laduradura", "5.15.2" do |s|
          s.platform = "java"
        end
        build_gem "laduradura", "5.15.3" do |s|
          s.platform = "java"
        end

        build_gem "weakling", "0.0.3"

        build_gem "terranova", "8"

        build_gem "duradura", "7.0"

        build_gem "very_simple_binary", &:add_c_extension
        build_gem "simple_binary", &:add_c_extension

        build_gem "bundler", "0.9" do |s|
          s.executables = "bundle"
          s.write "bin/bundle", "#!/usr/bin/env ruby\nputs 'FAIL'"
        end

        # The bundler 0.8 gem has a rubygems plugin that always loads :(
        build_gem "bundler", "0.8.1" do |s|
          s.write "lib/bundler/omg.rb", ""
          s.write "lib/rubygems_plugin.rb", "require 'bundler/omg' ; puts 'FAIL'"
        end

        # The yard gem iterates over Gem.source_index looking for plugins
        build_gem "yard" do |s|
          s.write "lib/yard.rb", <<-Y
            Gem::Specification.sort_by(&:name).each do |gem|
              puts gem.full_name
            end
          Y
        end

        build_gem "net-ssh"
        build_gem "net-sftp", "1.1.1" do |s|
          s.add_dependency "net-ssh", ">= 1.0.0", "< 1.99.0"
        end

        build_gem "foo"
      end
    end

    def build_repo2(**kwargs, &blk)
      FileUtils.cp_r gem_repo1, gem_repo2, remove_destination: true
      update_repo2(**kwargs, &blk) if block_given?
    end

    # A repo that has no pre-installed gems included. (The caller completely
    # determines the contents with the block.)
    #
    # If the repo already exists, `#update_repo` will be called.
    def build_repo3(**kwargs, &blk)
      if File.exist?(gem_repo3)
        update_repo(gem_repo3, &blk)
      else
        build_repo gem_repo3, **kwargs, &blk
      end
    end

    # Like build_repo3, this is a repo that has no pre-installed gems included.
    #
    # If the repo already exists, `#udpate_repo` will be called
    def build_repo4(**kwargs, &blk)
      if File.exist?(gem_repo4)
        update_repo gem_repo4, &blk
      else
        build_repo gem_repo4, **kwargs, &blk
      end
    end

    def update_repo2(**kwargs, &blk)
      update_repo(gem_repo2, **kwargs, &blk)
    end

    def update_repo3(&blk)
      update_repo(gem_repo3, &blk)
    end

    def build_security_repo
      build_repo security_repo do
        build_gem "myrack"

        build_gem "signed_gem" do |s|
          cert = "signing-cert.pem"
          pkey = "signing-pkey.pem"
          s.write cert, TEST_CERT
          s.write pkey, TEST_PKEY
          s.signing_key = pkey
          s.cert_chain = [cert]
        end
      end
    end

    # A minimal fake irb console
    def build_dummy_irb(version = "9.9.9")
      build_gem "irb", version do |s|
        s.write "lib/irb.rb", <<-RUBY
          class IRB
            class << self
              def toplevel_binding
                unless defined?(@toplevel_binding) && @toplevel_binding
                  TOPLEVEL_BINDING.eval %{
                    def self.__irb__; binding; end
                    IRB.instance_variable_set(:@toplevel_binding, __irb__)
                    class << self; undef __irb__; end
                  }
                end
                @toplevel_binding.eval('private')
                @toplevel_binding
              end

              def __irb__
                while line = gets
                  begin
                    puts eval(line, toplevel_binding).inspect.sub(/^"(.*)"$/, '=> \\1')
                  rescue Exception => e
                    puts "\#{e.class}: \#{e.message}"
                    puts e.backtrace.first
                  end
                end
              end
              alias start __irb__
            end
          end
        RUBY
      end
    end

    def build_repo(path, **kwargs, &blk)
      return if File.directory?(path)

      FileUtils.mkdir_p("#{path}/gems")

      update_repo(path,**kwargs, &blk)
    end

    def update_repo(path, build_compact_index: true)
      exempted_caller = Gem.ruby_version >= Gem::Version.new("3.4.0.dev") && RUBY_ENGINE != "jruby" ? "#{Module.nesting.first}#build_repo" : "build_repo"
      if path == gem_repo1 && caller_locations(1, 1).first.label != exempted_caller
        raise "Updating gem_repo1 is unsupported -- use gem_repo2 instead"
      end
      return unless block_given?
      @_build_path = "#{path}/gems"
      @_build_repo = File.basename(path)
      yield
      options = { build_compact: build_compact_index }
      Gem::Indexer.new(path, options).generate_index
    ensure
      @_build_path = nil
      @_build_repo = nil
    end

    def build_index(&block)
      index = Bundler::Index.new
      IndexBuilder.run(index, &block) if block_given?
      index
    end

    def build_spec(name, version = "0.0.1", platform = nil, &block)
      Array(version).map do |v|
        Gem::Specification.new do |s|
          s.name     = name
          s.version  = Gem::Version.new(v)
          s.platform = platform
          s.authors  = ["no one in particular"]
          s.summary  = "a gemspec used only for testing"
          DepBuilder.run(s, &block) if block_given?
        end
      end
    end

    def build_lib(name, *args, &blk)
      build_with(LibBuilder, name, args, &blk)
    end

    def build_bundler(*args, &blk)
      build_with(BundlerBuilder, "bundler", args, &blk)
    end

    def build_gem(name, *args, &blk)
      build_with(GemBuilder, name, args, &blk)
    end

    def build_git(name, *args, &block)
      opts = args.last.is_a?(Hash) ? args.last : {}
      builder = opts[:bare] ? GitBareBuilder : GitBuilder
      spec = build_with(builder, name, args, &block)
      GitReader.new(self, opts[:path] || lib_path(spec.full_name))
    end

    def update_git(name, *args, &block)
      opts = args.last.is_a?(Hash) ? args.last : {}
      spec = build_with(GitUpdater, name, args, &block)
      GitReader.new(self, opts[:path] || lib_path(spec.full_name))
    end

    def build_plugin(name, *args, &blk)
      build_with(PluginBuilder, name, args, &blk)
    end

    private

    def build_with(builder, name, args, &blk)
      @_build_path ||= nil
      @_build_repo ||= nil
      options  = args.last.is_a?(Hash) ? args.pop : {}
      versions = args.last || "1.0"
      spec     = nil

      options[:path] ||= @_build_path
      options[:source] ||= @_build_repo

      Array(versions).each do |version|
        spec = builder.new(self, name, version)
        yield spec if block_given?
        spec._build(options)
      end

      spec
    end

    class IndexBuilder
      include Builders

      def self.run(index, &block)
        new(index).run(&block)
      end

      def initialize(index)
        @index = index
      end

      def run(&block)
        instance_eval(&block)
      end

      def gem(*args, &block)
        build_spec(*args, &block).each do |s|
          @index << s
        end
      end

      def platforms(platforms)
        platforms.split(/\s+/).each do |platform|
          platform.gsub!(/^(mswin32)$/, 'x86-\1')
          yield Gem::Platform.new(platform)
        end
      end

      def versions(versions)
        versions.split(/\s+/).each {|version| yield v(version) }
      end
    end

    class DepBuilder
      include Builders

      def self.run(spec, &block)
        new(spec).run(&block)
      end

      def initialize(spec)
        @spec = spec
      end

      def run(&block)
        instance_eval(&block)
      end

      def runtime(name, requirements)
        @spec.add_runtime_dependency(name, requirements)
      end

      def development(name, requirements)
        @spec.add_development_dependency(name, requirements)
      end

      def required_ruby_version=(*reqs)
        @spec.required_ruby_version = *reqs
      end

      alias_method :dep, :runtime
    end

    class BundlerBuilder
      def initialize(context, name, version)
        @context = context
        @spec = Spec::Path.loaded_gemspec.dup
        @spec.version = version || Bundler::VERSION
      end

      def required_ruby_version
        @spec.required_ruby_version
      end

      def required_ruby_version=(x)
        @spec.required_ruby_version = x
      end

      def _build(options = {})
        full_name = "bundler-#{@spec.version}"
        build_path = (options[:build_path] || @context.tmp) + full_name
        bundler_path = build_path + "#{full_name}.gem"

        FileUtils.mkdir_p build_path

        @context.shipped_files.each do |shipped_file|
          target_shipped_file = shipped_file
          target_shipped_file = shipped_file.sub(/\Alibexec/, "exe") if @context.ruby_core?
          target_shipped_file = build_path + target_shipped_file
          target_shipped_dir = File.dirname(target_shipped_file)
          FileUtils.mkdir_p target_shipped_dir unless File.directory?(target_shipped_dir)
          FileUtils.cp File.expand_path(shipped_file, @context.source_root), target_shipped_file, preserve: true
        end

        @context.replace_version_file(@spec.version, dir: build_path)
        @context.replace_changelog(@spec.version, dir: build_path) if options[:released]

        Spec::BuildMetadata.write_build_metadata(dir: build_path, version: @spec.version.to_s)

        Dir.chdir build_path do
          Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
            Gem::Package.build(@spec)
          end
        end

        if block_given?
          yield(bundler_path)
        else
          FileUtils.mv bundler_path, options[:path]
        end
      ensure
        FileUtils.rm_rf build_path
      end
    end

    class LibBuilder
      def initialize(context, name, version)
        @context = context
        @name    = name
        @spec = Gem::Specification.new do |s|
          s.name        = name
          s.version     = version
          s.summary     = "This is just a fake gem for testing"
          s.description = "This is a completely fake gem, for testing purposes."
          s.author      = "no one"
          s.email       = "foo@bar.baz"
          s.homepage    = "http://example.com"
          s.license     = "MIT"
          s.required_ruby_version = ">= 3.0"
        end
        @files = {}
      end

      def method_missing(*args, &blk)
        @spec.send(*args, &blk)
      end

      def write(file, source = "")
        @files[file] = source
      end

      def executables=(val)
        @spec.executables = Array(val)
        @spec.executables.each do |file|
          executable = "#{@spec.bindir}/#{file}"
          shebang = "#!/usr/bin/env ruby\n"
          @spec.files << executable
          write executable, "#{shebang}require_relative '../lib/#{@name}' ; puts #{Builders.constantize(@name)}"
        end
      end

      def add_c_extension
        extensions << "ext/extconf.rb"
        write "ext/extconf.rb", <<-RUBY
          require "mkmf"

          extension_name = "#{name}_c"
          if extra_lib_dir = with_config("ext-lib")
            # add extra libpath if --with-ext-lib is
            # passed in as a build_arg
            dir_config extension_name, nil, extra_lib_dir
          else
            dir_config extension_name
          end
          create_makefile extension_name
        RUBY
        write "ext/#{name}.c", <<-C
          #include "ruby.h"

          void Init_#{name}_c(void) {
            rb_define_module("#{Builders.constantize(name)}_IN_C");
          }
        C
      end

      def _build(options)
        path = options[:path] || _default_path

        if options[:rubygems_version]
          @spec.rubygems_version = options[:rubygems_version]

          def @spec.validate(*); end
        end

        unless options[:no_default]
          gem_source = options[:source] || "path@#{path}"
          @files = _default_files.
                   merge("lib/#{entrypoint}/source.rb" => "#{Builders.constantize(name)}_SOURCE = #{gem_source.to_s.dump}").
                   merge(@files)
        end

        @spec.authors = ["no one"]
        @spec.files += @files.keys

        case options[:gemspec]
        when false
          # do nothing
        when :yaml
          @files["#{name}.gemspec"] = @spec.to_yaml
        else
          @files["#{name}.gemspec"] = @spec.to_ruby
        end

        @files.each do |file, source|
          full_path = Pathname.new(path).join(file)
          FileUtils.mkdir_p(full_path.dirname)
          File.open(full_path, "w") {|f| f.puts source }
          FileUtils.chmod("+x", full_path) if @spec.executables.map {|exe| "#{@spec.bindir}/#{exe}" }.include?(file)
        end
        path
      end

      def _default_files
        @_default_files ||= { "lib/#{entrypoint}.rb" => "#{Builders.constantize(name)} = '#{version}#{platform_string}'" }
      end

      def entrypoint
        name.tr("-", "/")
      end

      def _default_path
        @context.tmp("libs", @spec.full_name)
      end

      def platform_string
        " #{@spec.platform}" unless @spec.platform == Gem::Platform::RUBY
      end
    end

    class GitBuilder < LibBuilder
      def _build(options)
        default_branch = options[:default_branch] || "main"
        path = options[:path] || _default_path
        source = options[:source] || "git@#{path}"
        super(options.merge(path: path, source: source))
        @context.git("config --global init.defaultBranch #{default_branch}", path)
        @context.git("init", path)
        @context.git("add *", path)
        @context.git("config user.email lol@wut.com", path)
        @context.git("config user.name lolwut", path)
        @context.git("config commit.gpgsign false", path)
        @context.git("commit -m OMG_INITIAL_COMMIT", path)
      end
    end

    class GitBareBuilder < LibBuilder
      def _build(options)
        path = options[:path] || _default_path
        super(options.merge(path: path))
        @context.git("init --bare", path)
      end
    end

    class GitUpdater < LibBuilder
      def _build(options)
        libpath = options[:path] || _default_path
        update_gemspec = options[:gemspec] || false
        source = options[:source] || "git@#{libpath}"

        if branch = options[:branch]
          @context.git("checkout -b #{Shellwords.shellescape(branch)}", libpath)
        elsif tag = options[:tag]
          @context.git("tag #{Shellwords.shellescape(tag)}", libpath)
        elsif options[:remote]
          @context.git("remote add origin #{options[:remote]}", libpath)
        elsif options[:push]
          @context.git("push origin #{options[:push]}", libpath)
        end

        current_ref = @context.git("rev-parse HEAD", libpath).strip
        _default_files.keys.each do |path|
          _default_files[path] += "\n#{Builders.constantize(name)}_PREV_REF = '#{current_ref}'"
        end
        super(options.merge(path: libpath, gemspec: update_gemspec, source: source))
        @context.git("commit -am BUMP", libpath)
      end
    end

    class GitReader
      attr_reader :context, :path

      def initialize(context, path)
        @context = context
        @path = path
      end

      def ref_for(ref, len = nil)
        ref = context.git "rev-parse #{ref}", path
        ref = ref[0..len] if len
        ref
      end
    end

    class GemBuilder < LibBuilder
      def _build(opts)
        lib_path = opts[:lib_path] || @context.tmp(".tmp/#{@spec.full_name}")
        lib_path = super(opts.merge(path: lib_path, no_default: opts[:no_default]))
        destination = opts[:path] || _default_path
        FileUtils.mkdir_p(lib_path.join(destination))

        if [:yaml, false].include?(opts[:gemspec])
          Dir.chdir(lib_path) do
            Bundler.rubygems.build(@spec, opts[:skip_validation])
          end
        elsif opts[:skip_validation]
          @context.gem_command "build --force #{@spec.name}", dir: lib_path
        else
          Dir.chdir(lib_path) { Gem::Package.build(@spec) }
        end

        gem_path = File.expand_path("#{@spec.full_name}.gem", lib_path)
        if opts[:to_system]
          @context.system_gems gem_path, default: opts[:default]
        elsif opts[:to_bundle]
          @context.system_gems gem_path, path: @context.default_bundle_path
        else
          FileUtils.mv(gem_path, destination)
        end
      end

      def _default_path
        @context.gem_repo1("gems")
      end
    end

    class PluginBuilder < GemBuilder
      def _default_files
        @_default_files ||= {
          "lib/#{name}.rb" => "#{Builders.constantize(name)} = '#{version}#{platform_string}'",
          "plugins.rb" => "",
        }
      end
    end

    TEST_CERT = <<~CERT
      -----BEGIN CERTIFICATE-----
      MIIDNTCCAh2gAwIBAgIBATANBgkqhkiG9w0BAQsFADAnMQwwCgYDVQQDDAN5b3Ux
      FzAVBgoJkiaJk/IsZAEZFgdleGFtcGxlMB4XDTE1MDIwODAwMTIyM1oXDTQyMDYy
      NTAwMTIyM1owJzEMMAoGA1UEAwwDeW91MRcwFQYKCZImiZPyLGQBGRYHZXhhbXBs
      ZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMkupYkg3Nd1oXM3fo0d
      mVJBWNrni88lKDuIIQXwcKe6XCgiloZG708ecLTOws9+o9MkTl9Wtpf/WGXT98NK
      EPUYakd2Fv1SuD1jWYlP7iDR6hB3RkWBm5ziujYftVJ4ZrPD42PLjDASvlh75Tvr
      MeM7yq/qkcgNsd9dQyUvMNPks3tla9je7Dt7Auli2IN3CNXys7gIOfwJH0Bb/M6t
      y7oUfpoUKAfLzwe61abztgDu1lSNgdFBM1kcxYflyh/FkX5TlAcWeAXzLrnxAXGR
      UxXrxW4oPC+kZi/pDRBd7X4zQDx7bCmr1+FsS3M05i3w5E08Tt9iKRk4V8nCmE4i
      k6UCAwEAAaNsMGowCQYDVR0TBAIwADAOBgNVHQ8BAf8EBAMCB4AwHQYDVR0OBBYE
      FOOOFw5TNAqt/TcRRZEU3Dg/58XuMBYGA1UdEQQPMA2BC3lvdUBleGFtcGxlMBYG
      A1UdEgQPMA2BC3lvdUBleGFtcGxlMA0GCSqGSIb3DQEBCwUAA4IBAQAy3xnmobxU
      1SyhHvoIXTJmG0wt1DQ/Dqwjy362LpEf1UHt29wtg1Mph58eVtl93z5Vd2t4/O77
      E2BHpSu9ujc6/Br4+2uA/Qk/xRyLBtZAwty6J4uFvOOg985HonN+RCUZbKSUTmtA
      TZvNtIDAZFQ8Tu75K4gIBxDcz7biGi4i1VJ3F3GNCNeossr9IQwKvb+UWFq14U5R
      IzUnGgMIzcjUG2kKQvddRD1CjS+egtcLvShbOfm5bs4w4rfQ2FPF+Aaf9v7fxa/c
      Jrf3K+cB19eAy7O4nlPG1xurvnZd0QpqRk++werrBuKe1Pgga7YBLePfJhzwqcZv
      wVOSsB870yeO
      -----END CERTIFICATE-----
    CERT

    TEST_PKEY = <<~PKEY
      -----BEGIN RSA PRIVATE KEY-----
      MIIEowIBAAKCAQEAyS6liSDc13Whczd+jR2ZUkFY2ueLzyUoO4ghBfBwp7pcKCKW
      hkbvTx5wtM7Cz36j0yROX1a2l/9YZdP3w0oQ9RhqR3YW/VK4PWNZiU/uINHqEHdG
      RYGbnOK6Nh+1Unhms8PjY8uMMBK+WHvlO+sx4zvKr+qRyA2x311DJS8w0+Sze2Vr
      2N7sO3sC6WLYg3cI1fKzuAg5/AkfQFv8zq3LuhR+mhQoB8vPB7rVpvO2AO7WVI2B
      0UEzWRzFh+XKH8WRflOUBxZ4BfMuufEBcZFTFevFbig8L6RmL+kNEF3tfjNAPHts
      KavX4WxLczTmLfDkTTxO32IpGThXycKYTiKTpQIDAQABAoIBABpyrHEWRed5X7aN
      kXCBzKSN/LLChT8VNnB6bppLnV501yVbmV2hDlg2EJZkfCMvwIptwnPcKs2uqZ4G
      u2gMC6X9Bgkg/YK4u4nZJBiIzoMNYEUL48wYGYS1dcokaapO3nQ8M1+XjyAexrFL
      5btL1IIisScRTQWiGe6FtzcN43sSNkBISyDF5zG4Kodynqi0ekITmMl2q5XLWcsM
      KBnmZcRFEmFae2YYczVy8SXNApkZEvN69znvAX1iDNnZ3sJFchXo1nRPt4stOOKw
      mydgIYqaNQ22aF3OkblvoA4Y4m+X2Qt1sfkryKa5xTT7DSE81GmmazNI64EWqtES
      6Xde6P0CgYEA+V1vuSnE5fWX188abWMbVwNMC71WfHbntFmI+qwWYPEpickm+RGX
      DDfXs5unlVX4KUmjfplgavO29op1GZTuD9TlRnUAV0+0aJnNq4DY6XsHfD84qsBr
      gQGEHeJ1cMGNDnZR/EV3eudMalj9Qjpx9NoXNzMykb0/SUYZQemiqwcCgYEAzokC
      s0GoHVJqan4dfU0h0G5QPncrajW9DGG1ySxK/A2eqbVB8W2ZQx39OS26/Gydb31p
      cR7zm8PZpNbzLqlIMEbD4F6q22xxvYVtDx/HHPjxHMi87yxwQ9uLDUHoMa/LciTO
      djv3D1xTDDGxbpjmsdmINetunAs3htxku7JY5PMCgYBs3/TVvXzwgmhHm28Ib4sS
      VKgxP/uw4CGORsFd4SDsNp9SP3c6rAltFjyheMaUlzKApFwz/DdyuvIZdp5mCvZe
      BzALsS3y8SPtv6lixiDu3/6GqvvM4bKOYuESQzvPfVJfDB4DrTjben2MuUnqTqZO
      p6IXQc1EgIJPNcH1W1LgpQKBgAKZlPAevngIBpDqn4JpSyititMOevxuSr/yJvCu
      Xw9HOJ0YTAk3APvoT7y9h6IP1/eEU6R56EUotP+vOQZ4WRFKgsK7TllOxyvElzfe
      hYom1BoxqLc2Dv+7rsdu8fZWKTB5qCOy44xM9DquEXa79AN/IojTOuQ5++v1sErw
      ls/jAoGBANneGe9ogN51mYkrLyg1fhU1i24gFRq+sPGEvsCUoE6Vjw/lawQQ80T8
      v45TFqvhoGpgznqy3qxDJyguquZg6HN2yW6HE2Dvk7uk3XogcjdXgNDmWqb2j0eE
      z9pKzHCqfwNVPuYf44Znyo2YeyZ2kHn42MU73oXuFshUs3QHcH+P
      -----END RSA PRIVATE KEY-----
    PKEY
  end
end
