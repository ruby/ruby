# frozen_string_literal: true

require "bundler/current_ruby"

module Bundler
  class CLI::Exec
    attr_reader :options, :args, :cmd

    TRAPPED_SIGNALS = %w[INT].freeze

    def initialize(options, args)
      @options = options
      @cmd = args.shift
      @args = args

      if Bundler.current_ruby.ruby_2? && !Bundler.current_ruby.jruby?
        @args << { :close_others => !options.keep_file_descriptors? }
      elsif options.keep_file_descriptors?
        Bundler.ui.warn "Ruby version #{RUBY_VERSION} defaults to keeping non-standard file descriptors on Kernel#exec."
      end
    end

    def run
      validate_cmd!
      SharedHelpers.set_bundle_environment
      if bin_path = Bundler.which(cmd)
        if !Bundler.settings[:disable_exec_load] && ruby_shebang?(bin_path)
          return kernel_load(bin_path, *args)
        end
        # First, try to exec directly to something in PATH
        if Bundler.current_ruby.jruby_18?
          kernel_exec(bin_path, *args)
        else
          kernel_exec([bin_path, cmd], *args)
        end
      else
        # exec using the given command
        kernel_exec(cmd, *args)
      end
    end

  private

    def validate_cmd!
      return unless cmd.nil?
      Bundler.ui.error "bundler: exec needs a command to run"
      exit 128
    end

    def kernel_exec(*args)
      ui = Bundler.ui
      Bundler.ui = nil
      Kernel.exec(*args)
    rescue Errno::EACCES, Errno::ENOEXEC
      Bundler.ui = ui
      Bundler.ui.error "bundler: not executable: #{cmd}"
      exit 126
    rescue Errno::ENOENT
      Bundler.ui = ui
      Bundler.ui.error "bundler: command not found: #{cmd}"
      Bundler.ui.warn "Install missing gem executables with `bundle install`"
      exit 127
    end

    def kernel_load(file, *args)
      args.pop if args.last.is_a?(Hash)
      ARGV.replace(args)
      $0 = file
      Process.setproctitle(process_title(file, args)) if Process.respond_to?(:setproctitle)
      ui = Bundler.ui
      Bundler.ui = nil
      require "bundler/setup"
      TRAPPED_SIGNALS.each {|s| trap(s, "DEFAULT") }
      Kernel.load(file)
    rescue SystemExit, SignalException
      raise
    rescue Exception => e # rubocop:disable Lint/RescueException
      Bundler.ui = ui
      Bundler.ui.error "bundler: failed to load command: #{cmd} (#{file})"
      backtrace = e.backtrace ? e.backtrace.take_while {|bt| !bt.start_with?(__FILE__) } : []
      abort "#{e.class}: #{e.message}\n  #{backtrace.join("\n  ")}"
    end

    def process_title(file, args)
      "#{file} #{args.join(" ")}".strip
    end

    def ruby_shebang?(file)
      possibilities = [
        "#!/usr/bin/env ruby\n",
        "#!/usr/bin/env jruby\n",
        "#!/usr/bin/env truffleruby\n",
        "#!#{Gem.ruby}\n",
      ]

      if File.zero?(file)
        Bundler.ui.warn "#{file} is empty"
        return false
      end

      first_line = File.open(file, "rb") {|f| f.read(possibilities.map(&:size).max) }
      possibilities.any? {|shebang| first_line.start_with?(shebang) }
    end
  end
end
