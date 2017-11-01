# frozen_string_literal: true

module Spec
  module Helpers
    def reset!
      Dir.glob("#{tmp}/{gems/*,*}", File::FNM_DOTMATCH).each do |dir|
        next if %w[base remote1 gems rubygems . ..].include?(File.basename(dir))
        if ENV["BUNDLER_SUDO_TESTS"]
          `sudo rm -rf "#{dir}"`
        else
          FileUtils.rm_rf(dir)
        end
      end
      FileUtils.mkdir_p(home)
      FileUtils.mkdir_p(tmpdir)
      Bundler.reset!
      Bundler.ui = nil
      Bundler.ui # force it to initialize
    end

    def self.bang(method)
      define_method("#{method}!") do |*args, &blk|
        send(method, *args, &blk).tap do
          unless last_command.success?
            raise RuntimeError,
              "Invoking #{method}!(#{args.map(&:inspect).join(", ")}) failed:\n#{last_command.stdboth}",
              caller.drop_while {|bt| bt.start_with?(__FILE__) }
          end
        end
      end
    end

    def the_bundle(*args)
      TheBundle.new(*args)
    end

    def last_command
      @command_executions.last || raise("There is no last command")
    end

    def out
      last_command.stdboth
    end

    def err
      last_command.stderr
    end

    def exitstatus
      last_command.exitstatus
    end

    def bundle_update_requires_all?
      Bundler::VERSION.start_with?("1.") ? nil : true
    end

    def in_app_root(&blk)
      Dir.chdir(bundled_app, &blk)
    end

    def in_app_root2(&blk)
      Dir.chdir(bundled_app2, &blk)
    end

    def in_app_root_custom(root, &blk)
      Dir.chdir(root, &blk)
    end

    def run(cmd, *args)
      opts = args.last.is_a?(Hash) ? args.pop : {}
      groups = args.map(&:inspect).join(", ")
      setup = "require 'rubygems' ; require 'bundler' ; Bundler.setup(#{groups})\n"
      ruby(setup + cmd, opts)
    end
    bang :run

    def load_error_run(ruby, name, *args)
      cmd = <<-RUBY
        begin
          #{ruby}
        rescue LoadError => e
          $stderr.puts "ZOMG LOAD ERROR" if e.message.include?("-- #{name}")
        end
      RUBY
      opts = args.last.is_a?(Hash) ? args.pop : {}
      args += [opts]
      run(cmd, *args)
    end

    def lib
      root.join("lib")
    end

    def spec
      spec_dir.to_s
    end

    def bundle(cmd, options = {})
      with_sudo = options.delete(:sudo)
      sudo = with_sudo == :preserve_env ? "sudo -E" : "sudo" if with_sudo

      no_color = options.delete("no-color") { cmd.to_s !~ /\A(e|ex|exe|exec|conf|confi|config)(\s|\z)/ }
      options["no-color"] = true if no_color

      bundle_bin = options.delete("bundle_bin") || bindir.join("bundle")

      if system_bundler = options.delete(:system_bundler)
        bundle_bin = "-S bundle"
      end

      env = options.delete(:env) || {}
      env["PATH"].gsub!("#{Path.root}/exe", "") if env["PATH"] && system_bundler

      requires = options.delete(:requires) || []
      requires << "support/hax"

      artifice = options.delete(:artifice) do
        if RSpec.current_example.metadata[:realworld]
          "vcr"
        else
          "fail"
        end
      end
      if artifice
        requires << File.expand_path("../artifice/#{artifice}", __FILE__)
      end

      requires_str = requires.map {|r| "-r#{r}" }.join(" ")

      load_path = []
      load_path << lib unless system_bundler
      load_path << spec
      load_path_str = "-I#{load_path.join(File::PATH_SEPARATOR)}"

      env = env.map {|k, v| "#{k}='#{v}'" }.join(" ")

      args = options.map do |k, v|
        case v
        when nil
          next
        when true
          " --#{k}"
        when false
          " --no-#{k}"
        else
          " --#{k} #{v}"
        end
      end.join

      cmd = "#{env} #{sudo} #{Gem.ruby} #{load_path_str} #{requires_str} #{bundle_bin} #{cmd}#{args}"
      sys_exec(cmd) {|i, o, thr| yield i, o, thr if block_given? }
    end
    bang :bundle

    def forgotten_command_line_options(options)
      remembered = Bundler::VERSION.split(".", 2).first == "1"
      options = options.map do |k, v|
        k = Array(k)[remembered ? 0 : -1]
        v = '""' if v && v.to_s.empty?
        [k, v]
      end
      return Hash[options] if remembered
      options.each do |k, v|
        if v.nil?
          bundle! "config --delete #{k}"
        else
          bundle! "config --local #{k} #{v}"
        end
      end
      {}
    end

    def bundler(cmd, options = {})
      options["bundle_bin"] = bindir.join("bundler")
      bundle(cmd, options)
    end

    def bundle_ruby(options = {})
      options["bundle_bin"] = bindir.join("bundle_ruby")
      bundle("", options)
    end

    def ruby(ruby, options = {})
      env = (options.delete(:env) || {}).map {|k, v| "#{k}='#{v}' " }.join
      ruby = ruby.gsub(/["`\$]/) {|m| "\\#{m}" }
      lib_option = options[:no_lib] ? "" : " -I#{lib}"
      sys_exec(%(#{env}#{Gem.ruby}#{lib_option} -e "#{ruby}"))
    end
    bang :ruby

    def load_error_ruby(ruby, name, opts = {})
      ruby(<<-R)
        begin
          #{ruby}
        rescue LoadError => e
          $stderr.puts "ZOMG LOAD ERROR"# if e.message.include?("-- #{name}")
        end
      R
    end

    def gembin(cmd)
      lib = File.expand_path("../../../lib", __FILE__)
      old = ENV["RUBYOPT"]
      ENV["RUBYOPT"] = "#{ENV["RUBYOPT"]} -I#{lib}"
      cmd = bundled_app("bin/#{cmd}") unless cmd.to_s.include?("/")
      sys_exec(cmd.to_s)
    ensure
      ENV["RUBYOPT"] = old
    end

    def gem_command(command, args = "", options = {})
      if command == :exec && !options[:no_quote]
        args = args.gsub(/(?=")/, "\\")
        args = %("#{args}")
      end
      gem = ENV['BUNDLE_GEM'] || "#{Gem.ruby} -rrubygems -S gem --backtrace"
      sys_exec("#{gem} #{command} #{args}")
    end
    bang :gem_command

    def rake
      if ENV['BUNDLE_RUBY'] && ENV['BUNDLE_GEM']
        "#{ENV['BUNDLE_RUBY']} #{ENV['GEM_PATH']}/bin/rake"
      else
        'rake'
      end
    end

    def sys_exec(cmd)
      command_execution = CommandExecution.new(cmd.to_s, Dir.pwd)

      Open3.popen3(cmd.to_s) do |stdin, stdout, stderr, wait_thr|
        yield stdin, stdout, wait_thr if block_given?
        stdin.close

        command_execution.exitstatus = wait_thr && wait_thr.value.exitstatus
        command_execution.stdout = Thread.new { stdout.read }.value.strip
        command_execution.stderr = Thread.new { stderr.read }.value.strip
      end

      (@command_executions ||= []) << command_execution

      command_execution.stdout
    end
    bang :sys_exec

    def config(config = nil, path = bundled_app(".bundle/config"))
      return YAML.load_file(path) unless config
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, "w") do |f|
        f.puts config.to_yaml
      end
      config
    end

    def global_config(config = nil)
      config(config, home(".bundle/config"))
    end

    def create_file(*args)
      path = bundled_app(args.shift)
      path = args.shift if args.first.is_a?(Pathname)
      str  = args.shift || ""
      path.dirname.mkpath
      File.open(path.to_s, "w") do |f|
        f.puts strip_whitespace(str)
      end
    end

    def gemfile(*args)
      if args.empty?
        File.open("Gemfile", "r", &:read)
      else
        create_file("Gemfile", *args)
      end
    end

    def lockfile(*args)
      if args.empty?
        File.open("Gemfile.lock", "r", &:read)
      else
        create_file("Gemfile.lock", *args)
      end
    end

    def strip_whitespace(str)
      # Trim the leading spaces
      spaces = str[/\A\s+/, 0] || ""
      str.gsub(/^#{spaces}/, "")
    end

    def install_gemfile(*args)
      gemfile(*args)
      opts = args.last.is_a?(Hash) ? args.last : {}
      opts[:retry] ||= 0
      bundle :install, opts
    end
    bang :install_gemfile

    def lock_gemfile(*args)
      gemfile(*args)
      opts = args.last.is_a?(Hash) ? args.last : {}
      opts[:retry] ||= 0
      bundle :lock, opts
    end

    def install_gems(*gems)
      options = gems.last.is_a?(Hash) ? gems.pop : {}
      gem_repo = options.fetch(:gem_repo) { gem_repo1 }
      gems.each do |g|
        path = if g == :bundler
          Dir.chdir(root) { gem_command! :build, gemspec.to_s }
          bundler_path = root + "bundler-#{Bundler::VERSION}.gem"
        elsif g.to_s =~ %r{\A/.*\.gem\z}
          g
        else
          "#{gem_repo}/gems/#{g}.gem"
        end

        raise "OMG `#{path}` does not exist!" unless File.exist?(path)

        gem_command! :install, "--no-rdoc --no-ri --ignore-dependencies '#{path}'"
        bundler_path && bundler_path.rmtree
      end
    end

    alias_method :install_gem, :install_gems

    def with_gem_path_as(path)
      backup = ENV.to_hash
      ENV["GEM_HOME"] = path.to_s
      ENV["GEM_PATH"] = path.to_s
      ENV["BUNDLER_ORIG_GEM_PATH"] = nil
      yield
    ensure
      ENV.replace(backup)
    end

    def with_path_as(path)
      backup = ENV.to_hash
      ENV["PATH"] = path.to_s
      ENV["BUNDLER_ORIG_PATH"] = nil
      yield
    ensure
      ENV.replace(backup)
    end

    def with_path_added(path)
      with_path_as(path.to_s + ":" + ENV["PATH"]) do
        yield
      end
    end

    def break_git!
      FileUtils.mkdir_p(tmp("broken_path"))
      File.open(tmp("broken_path/git"), "w", 0o755) do |f|
        f.puts "#!/usr/bin/env ruby\nSTDERR.puts 'This is not the git you are looking for'\nexit 1"
      end

      ENV["PATH"] = "#{tmp("broken_path")}:#{ENV["PATH"]}"
    end

    def with_fake_man
      FileUtils.mkdir_p(tmp("fake_man"))
      File.open(tmp("fake_man/man"), "w", 0o755) do |f|
        f.puts "#!/usr/bin/env ruby\nputs ARGV.inspect\n"
      end
      with_path_added(tmp("fake_man")) { yield }
    end

    def system_gems(*gems)
      opts = gems.last.is_a?(Hash) ? gems.last : {}
      path = opts.fetch(:path, system_gem_path)
      if path == :bundle_path
        path = ruby!(<<-RUBY)
          require "bundler"
          begin
            puts Bundler.bundle_path
          rescue Bundler::GemfileNotFound
            ENV["BUNDLE_GEMFILE"] = "Gemfile"
            retry
          end

        RUBY
      end
      gems = gems.flatten

      unless opts[:keep_path]
        FileUtils.rm_rf(path)
        FileUtils.mkdir_p(path)
      end

      Gem.clear_paths

      env_backup = ENV.to_hash
      ENV["GEM_HOME"] = path.to_s
      ENV["GEM_PATH"] = path.to_s
      ENV["BUNDLER_ORIG_GEM_PATH"] = nil

      install_gems(*gems)
      return unless block_given?
      begin
        yield
      ensure
        ENV.replace(env_backup)
      end
    end

    def realworld_system_gems(*gems)
      gems = gems.flatten

      FileUtils.rm_rf(system_gem_path)
      FileUtils.mkdir_p(system_gem_path)

      Gem.clear_paths

      gem_home = ENV["GEM_HOME"]
      gem_path = ENV["GEM_PATH"]
      path = ENV["PATH"]
      ENV["GEM_HOME"] = system_gem_path.to_s
      ENV["GEM_PATH"] = system_gem_path.to_s

      gems.each do |gem|
        gem_command :install, "--no-rdoc --no-ri #{gem}"
      end
      return unless block_given?
      begin
        yield
      ensure
        ENV["GEM_HOME"] = gem_home
        ENV["GEM_PATH"] = gem_path
        ENV["PATH"] = path
      end
    end

    def cache_gems(*gems)
      gems = gems.flatten

      FileUtils.rm_rf("#{bundled_app}/vendor/cache")
      FileUtils.mkdir_p("#{bundled_app}/vendor/cache")

      gems.each do |g|
        path = "#{gem_repo1}/gems/#{g}.gem"
        raise "OMG `#{path}` does not exist!" unless File.exist?(path)
        FileUtils.cp(path, "#{bundled_app}/vendor/cache")
      end
    end

    def simulate_new_machine
      system_gems []
      FileUtils.rm_rf system_gem_path
      FileUtils.rm_rf bundled_app(".bundle")
    end

    def simulate_platform(platform)
      old = ENV["BUNDLER_SPEC_PLATFORM"]
      ENV["BUNDLER_SPEC_PLATFORM"] = platform.to_s
      yield if block_given?
    ensure
      ENV["BUNDLER_SPEC_PLATFORM"] = old if block_given?
    end

    def simulate_ruby_version(version)
      return if version == RUBY_VERSION
      old = ENV["BUNDLER_SPEC_RUBY_VERSION"]
      ENV["BUNDLER_SPEC_RUBY_VERSION"] = version
      yield if block_given?
    ensure
      ENV["BUNDLER_SPEC_RUBY_VERSION"] = old if block_given?
    end

    def simulate_ruby_engine(engine, version = "1.6.0")
      return if engine == local_ruby_engine

      old = ENV["BUNDLER_SPEC_RUBY_ENGINE"]
      ENV["BUNDLER_SPEC_RUBY_ENGINE"] = engine
      old_version = ENV["BUNDLER_SPEC_RUBY_ENGINE_VERSION"]
      ENV["BUNDLER_SPEC_RUBY_ENGINE_VERSION"] = version
      yield if block_given?
    ensure
      ENV["BUNDLER_SPEC_RUBY_ENGINE"] = old if block_given?
      ENV["BUNDLER_SPEC_RUBY_ENGINE_VERSION"] = old_version if block_given?
    end

    def simulate_bundler_version(version)
      old = ENV["BUNDLER_SPEC_VERSION"]
      ENV["BUNDLER_SPEC_VERSION"] = version.to_s
      yield if block_given?
    ensure
      ENV["BUNDLER_SPEC_VERSION"] = old if block_given?
    end

    def simulate_rubygems_version(version)
      old = ENV["BUNDLER_SPEC_RUBYGEMS_VERSION"]
      ENV["BUNDLER_SPEC_RUBYGEMS_VERSION"] = version.to_s
      yield if block_given?
    ensure
      ENV["BUNDLER_SPEC_RUBYGEMS_VERSION"] = old if block_given?
    end

    def simulate_windows
      old = ENV["BUNDLER_SPEC_WINDOWS"]
      ENV["BUNDLER_SPEC_WINDOWS"] = "true"
      simulate_platform mswin do
        yield
      end
    ensure
      ENV["BUNDLER_SPEC_WINDOWS"] = old
    end

    def revision_for(path)
      Dir.chdir(path) { `git rev-parse HEAD`.strip }
    end

    def capture_output
      capture(:stdout)
    end

    def with_read_only(pattern)
      chmod = lambda do |dirmode, filemode|
        lambda do |f|
          mode = File.directory?(f) ? dirmode : filemode
          File.chmod(mode, f)
        end
      end

      Dir[pattern].each(&chmod[0o555, 0o444])
      yield
    ensure
      Dir[pattern].each(&chmod[0o755, 0o644])
    end

    def process_file(pathname)
      changed_lines = pathname.readlines.map do |line|
        yield line
      end
      File.open(pathname, "w") {|file| file.puts(changed_lines.join) }
    end

    def with_env_vars(env_hash, &block)
      current_values = {}
      env_hash.each do |k, v|
        current_values[k] = ENV[k]
        ENV[k] = v
      end
      block.call if block_given?
      env_hash.each do |k, _|
        ENV[k] = current_values[k]
      end
    end

    def require_rack
      # need to hack, so we can require rack
      old_gem_home = ENV["GEM_HOME"]
      ENV["GEM_HOME"] = Spec::Path.base_system_gems.to_s
      require "rack"
      ENV["GEM_HOME"] = old_gem_home
    end

    def wait_for_server(host, port, seconds = 15)
      tries = 0
      sleep 0.5
      TCPSocket.new(host, port)
    rescue => e
      raise(e) if tries > (seconds * 2)
      tries += 1
      retry
    end

    def find_unused_port
      port = 21_453
      begin
        port += 1 while TCPSocket.new("127.0.0.1", port)
      rescue
        false
      end
      port
    end

    def bundler_fileutils
      if RUBY_VERSION >= "2.4"
        ::Bundler::FileUtils
      else
        ::FileUtils
      end
    end
  end
end
