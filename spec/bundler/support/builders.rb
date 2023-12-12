# frozen_string_literal: true

require "bundler/shared_helpers"
require "shellwords"

module Spec
  module Builders
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
      rake_path = Dir["#{Path.base_system_gems}/**/rake*.gem"].first

      build_repo gem_repo1 do
        FileUtils.cp rake_path, "#{gem_repo1}/gems/"

        build_gem "coffee-script-source"
        build_gem "git"
        build_gem "puma"
        build_gem "minitest"

        build_gem "rack", %w[0.9.1 1.0.0] do |s|
          s.executables = "rackup"
          s.post_install_message = "Rack's post install message"
        end

        build_gem "thin" do |s|
          s.add_dependency "rack"
          s.post_install_message = "Thin's post install message"
        end

        build_gem "rack-obama" do |s|
          s.add_dependency "rack"
          s.post_install_message = "Rack-obama's post install message"
        end

        build_gem "rack_middleware", "1.0" do |s|
          s.add_dependency "rack", "0.9.1"
        end

        build_gem "rails", "2.3.2" do |s|
          s.executables = "rails"
          s.add_dependency "rake",           "13.0.1"
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

        build_gem "rack-test", no_default: true do |s|
          s.write "lib/rack/test.rb", "RACK_TEST = '1.0'"
        end

        build_gem "platform_specific" do |s|
          s.platform = Gem::Platform.local
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0.0 #{Gem::Platform.local}'"
        end

        build_gem "platform_specific" do |s|
          s.platform = "java"
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0.0 JAVA'"
        end

        build_gem "platform_specific" do |s|
          s.platform = "ruby"
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0.0 RUBY'"
        end

        build_gem "platform_specific" do |s|
          s.platform = "x86-mswin32"
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0 x86-mswin32'"
        end

        build_gem "platform_specific" do |s|
          s.platform = "x64-mswin64"
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0 x64-mswin64'"
        end

        build_gem "platform_specific" do |s|
          s.platform = "x86-mingw32"
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0 x86-mingw32'"
        end

        build_gem "platform_specific" do |s|
          s.platform = "x64-mingw32"
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0 x64-mingw32'"
        end

        build_gem "platform_specific" do |s|
          s.platform = "x64-mingw-ucrt"
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0 x64-mingw-ucrt'"
        end

        build_gem "platform_specific" do |s|
          s.platform = "x86-darwin-100"
          s.write "lib/platform_specific.rb", "PLATFORM_SPECIFIC = '1.0.0 x86-darwin-100'"
        end

        build_gem "only_java", "1.0" do |s|
          s.platform = "java"
          s.write "lib/only_java.rb", "ONLY_JAVA = '1.0.0 JAVA'"
        end

        build_gem "only_java", "1.1" do |s|
          s.platform = "java"
          s.write "lib/only_java.rb", "ONLY_JAVA = '1.1.0 JAVA'"
        end

        build_gem "nokogiri", "1.4.2"
        build_gem "nokogiri", "1.4.2" do |s|
          s.platform = "java"
          s.write "lib/nokogiri.rb", "NOKOGIRI = '1.4.2 JAVA'"
          s.add_dependency "weakling", ">= 0.0.3"
        end

        build_gem "laduradura", "5.15.2"
        build_gem "laduradura", "5.15.2" do |s|
          s.platform = "java"
          s.write "lib/laduradura.rb", "LADURADURA = '5.15.2 JAVA'"
        end
        build_gem "laduradura", "5.15.3" do |s|
          s.platform = "java"
          s.write "lib/laduradura.rb", "LADURADURA = '5.15.2 JAVA'"
        end

        build_gem "weakling", "0.0.3"

        build_gem "terranova", "8"

        build_gem "duradura", "7.0"

        build_gem "very_simple_binary", &:add_c_extension
        build_gem "simple_binary", &:add_c_extension

        build_gem "bundler", "0.9" do |s|
          s.executables = "bundle"
          s.write "bin/bundle", "puts 'FAIL'"
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
      FileUtils.rm_rf gem_repo2
      FileUtils.cp_r gem_repo1, gem_repo2
      update_repo2(**kwargs, &blk) if block_given?
    end

    # A repo that has no pre-installed gems included. (The caller completely
    # determines the contents with the block.)
    def build_repo4(**kwargs, &blk)
      FileUtils.rm_rf gem_repo4
      build_repo(gem_repo4, **kwargs, &blk)
    end

    def update_repo4(&blk)
      update_repo(gem_repo4, &blk)
    end

    def update_repo2(**kwargs, &blk)
      update_repo(gem_repo2, **kwargs, &blk)
    end

    def build_security_repo
      build_repo security_repo do
        build_gem "rack"

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

    def build_repo(path, **kwargs, &blk)
      return if File.directory?(path)

      FileUtils.mkdir_p("#{path}/gems")

      update_repo(path,**kwargs, &blk)
    end

    def check_test_gems!
      rake_path = Dir["#{Path.base_system_gems}/**/rake*.gem"].first

      if rake_path.nil?
        FileUtils.rm_rf(Path.base_system_gems)
        Spec::Rubygems.install_test_deps
        rake_path = Dir["#{Path.base_system_gems}/**/rake*.gem"].first
      end

      if rake_path.nil?
        abort "Your test gems are missing! Run `rm -rf #{tmp}` and try again."
      end
    end

    def update_repo(path, build_compact_index: true)
      if path == gem_repo1 && caller.first.split(" ").last == "`build_repo`"
        raise "Updating gem_repo1 is unsupported -- use gem_repo2 instead"
      end
      return unless block_given?
      @_build_path = "#{path}/gems"
      @_build_repo = File.basename(path)
      yield
      with_gem_path_as Path.base_system_gem_path do
        Dir[Spec::Path.base_system_gem_path.join("gems/rubygems-generate_index*/lib")].first ||
          raise("Could not find rubygems-generate_index lib directory in #{Spec::Path.base_system_gem_path}")

        command = "generate_index"
        command += " --no-compact" if !build_compact_index && gem_command(command + " --help").include?("--[no-]compact")
        gem_command command, dir: path
      end
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
          shebang = if Bundler.current_ruby.jruby?
            "#!/usr/bin/env jruby\n"
          else
            "#!/usr/bin/env ruby\n"
          end
          @spec.files << executable
          write executable, "#{shebang}require_relative '../lib/#{@name}' ; puts #{Builders.constantize(@name)}"
        end
      end

      def add_c_extension
        require_paths << "ext"
        extensions << "ext/extconf.rb"
        write "ext/extconf.rb", <<-RUBY
          require "mkmf"

          $extout = "$(topdir)/" + RbConfig::CONFIG["EXTOUT"]

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

          void Init_#{name}_c() {
            rb_define_module("#{Builders.constantize(name)}_IN_C");
          }
        C
      end

      def _build(options)
        path = options[:path] || _default_path

        if options[:rubygems_version]
          @spec.rubygems_version = options[:rubygems_version]
          def @spec.mark_version; end

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
          @spec.files << "#{name}.gemspec"
          @files["#{name}.gemspec"] = @spec.to_yaml
        else
          @spec.files << "#{name}.gemspec"
          @files["#{name}.gemspec"] = @spec.to_ruby
        end

        @files.each do |file, source|
          file = Pathname.new(path).join(file)
          FileUtils.mkdir_p(file.dirname)
          File.open(file, "w") {|f| f.puts source }
          File.chmod("+x", file) if @spec.executables.map {|exe| "#{@spec.bindir}/#{exe}" }.include?(file)
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

        if opts[:gemspec] == :yaml || opts[:gemspec] == false
          Dir.chdir(lib_path) do
            Bundler.rubygems.build(@spec, opts[:skip_validation])
          end
        elsif opts[:skip_validation]
          @context.gem_command "build --force #{@spec.name}", dir: lib_path
        else
          @context.gem_command "build #{@spec.name}", dir: lib_path
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
      MIIDMjCCAhqgAwIBAgIBATANBgkqhkiG9w0BAQUFADAnMQwwCgYDVQQDDAN5b3Ux
      FzAVBgoJkiaJk/IsZAEZFgdleGFtcGxlMB4XDTE1MDIwODAwMTIyM1oXDTQyMDYy
      NTAwMTIyM1owJzEMMAoGA1UEAwwDeW91MRcwFQYKCZImiZPyLGQBGRYHZXhhbXBs
      ZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANlvFdpN43c4DMS9Jo06
      m0a7k3bQ3HWQ1yrYhZMi77F1F73NpBknYHIzDktQpGn6hs/4QFJT4m4zNEBF47UL
      jHU5nTK5rjkS3niGYUjvh3ZEzVeo9zHUlD/UwflDo4ALl3TSo2KY/KdPS/UTdLXL
      ajkQvaVJtEDgBPE3DPhlj5whp+Ik3mDHej7qpV6F502leAwYaFyOtlEG/ZGNG+nZ
      L0clH0j77HpP42AylHDi+vakEM3xcjo9BeWQ6Vkboic93c9RTt6CWBWxMQP7Nol1
      MOebz9XOSQclxpxWteXNfPRtMdAhmRl76SMI8ywzThNPpa4EH/yz34ftebVOgKyM
      nd0CAwEAAaNpMGcwCQYDVR0TBAIwADALBgNVHQ8EBAMCBLAwHQYDVR0OBBYEFA7D
      n9qo0np23qi3aOYuAAPn/5IdMBYGA1UdEQQPMA2BC3lvdUBleGFtcGxlMBYGA1Ud
      EgQPMA2BC3lvdUBleGFtcGxlMA0GCSqGSIb3DQEBBQUAA4IBAQA7Gyk62sWOUX/N
      vk4tJrgKESph6Ns8+E36A7n3jt8zCep8ldzMvwTWquf9iqhsC68FilEoaDnUlWw7
      d6oNuaFkv7zfrWGLlvqQJC+cu2X5EpcCksg5oRp8VNbwJysJ6JgwosxzROII8eXc
      R+j1j6mDvQYqig2QOnzf480pjaqbP+tspfDFZbhKPrgM3Blrb3ZYuFpv4zkqI7aB
      6fuk2DUhNO1CuwrJA84TqC+jGo73bDKaT5hrIDiaJRrN5+zcWja2uEWrj5jSbep4
      oXdEdyH73hOHMBP40uds3PqnUsxEJhzjB2sCCe1geV24kw9J4m7EQXPVkUKDgKrt
      LlpDmOoo
      -----END CERTIFICATE-----
    CERT

    TEST_PKEY = <<~PKEY
      -----BEGIN RSA PRIVATE KEY-----
      MIIEowIBAAKCAQEA2W8V2k3jdzgMxL0mjTqbRruTdtDcdZDXKtiFkyLvsXUXvc2k
      GSdgcjMOS1CkafqGz/hAUlPibjM0QEXjtQuMdTmdMrmuORLeeIZhSO+HdkTNV6j3
      MdSUP9TB+UOjgAuXdNKjYpj8p09L9RN0tctqORC9pUm0QOAE8TcM+GWPnCGn4iTe
      YMd6PuqlXoXnTaV4DBhoXI62UQb9kY0b6dkvRyUfSPvsek/jYDKUcOL69qQQzfFy
      Oj0F5ZDpWRuiJz3dz1FO3oJYFbExA/s2iXUw55vP1c5JByXGnFa15c189G0x0CGZ
      GXvpIwjzLDNOE0+lrgQf/LPfh+15tU6ArIyd3QIDAQABAoIBACbDqz20TS1gDMa2
      gj0DidNedbflHKjJHdNBru7Ad8NHgOgR1YO2hXdWquG6itVqGMbTF4SV9/R1pIcg
      7qvEV1I+50u31tvOBWOvcYCzU48+TO2n7gowQA3xPHPYHzog1uu48fAOHl0lwgD7
      av9OOK3b0jO5pC08wyTOD73pPWU0NrkTh2+N364leIi1pNuI1z4V+nEuIIm7XpVd
      5V4sXidMTiEMJwE6baEDfTjHKaoRndXrrPo3ryIXmcX7Ag1SwAQwF5fBCRToCgIx
      dszEZB1bJD5gA6r+eGnJLB/F60nK607az5o3EdguoB2LKa6q6krpaRCmZU5svvoF
      J7xgBPECgYEA8RIzHAQ3zbaibKdnllBLIgsqGdSzebTLKheFuigRotEV3Or/z5Lg
      k/nVnThWVkTOSRqXTNpJAME6a4KTdcVSxYP+SdZVO1esazHrGb7xPVb7MWSE1cqp
      WEk3Yy8OUOPoPQMc4dyGzd30Mi8IBB6gnFIYOTrpUo0XtkBv8rGGhfsCgYEA5uYn
      6QgL4NqNT84IXylmMb5ia3iBt6lhxI/A28CDtQvfScl4eYK0IjBwdfG6E1vJgyzg
      nJzv3xEVo9bz+Kq7CcThWpK5JQaPnsV0Q74Wjk0ShHet15txOdJuKImnh5F6lylC
      GTLR9gnptytfMH/uuw4ws0Q2kcg4l5NHKOWOnAcCgYEAvAwIVkhsB0n59Wu4gCZu
      FUZENxYWUk/XUyQ6KnZrG2ih90xQ8+iMyqFOIm/52R2fFKNrdoWoALC6E3ct8+ZS
      pMRLrelFXx8K3it4SwMJR2H8XBEfFW4bH0UtsW7Zafv+AunUs9LETP5gKG1LgXsq
      qgXX43yy2LQ61O365YPZfdUCgYBVbTvA3MhARbvYldrFEnUL3GtfZbNgdxuD9Mee
      xig0eJMBIrgfBLuOlqtVB70XYnM4xAbKCso4loKSHnofO1N99siFkRlM2JOUY2tz
      kMWZmmxKdFjuF0WZ5f/5oYxI/QsFGC+rUQEbbWl56mMKd5qkvEhKWudxoklF0yiV
      ufC8SwKBgDWb8iWqWN5a/kfvKoxFcDM74UHk/SeKMGAL+ujKLf58F+CbweM5pX9C
      EUsxeoUEraVWTiyFVNqD81rCdceus9TdBj0ZIK1vUttaRZyrMAwF0uQSfjtxsOpd
      l69BkyvzjgDPkmOHVGiSZDLi3YDvypbUpo6LOy4v5rVg5U2F/A0v
      -----END RSA PRIVATE KEY-----
    PKEY
  end
end
