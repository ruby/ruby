# frozen_string_literal: true

require_relative "command_execution"

module Spec
  module Subprocess
    class TimeoutExceeded < StandardError; end

    def command_executions
      @command_executions ||= []
    end

    def last_command
      command_executions.last || raise("There is no last command")
    end

    def out
      last_command.stdout
    end

    def err
      last_command.stderr
    end

    def stdboth
      last_command.stdboth
    end

    def exitstatus
      last_command.exitstatus
    end

    def git(cmd, path = Dir.pwd, options = {})
      reject_git_config_pollution!(cmd, path)
      sh("git #{cmd}", options.merge(dir: path))
    end

    # A local `git config` write in a directory without a `.git` makes git
    # discover an enclosing repository, which can be the rubygems checkout
    # itself, polluting its (possibly worktree-shared) `.git/config` with
    # fixture identities. Only allow local config writes inside tmp/.
    def reject_git_config_pollution!(cmd, path)
      require "shellwords"
      args = cmd.to_s.shellsplit
      return unless args.first == "config"
      return if args.any? {|a| ["--global", "--system", "-f", "--file"].include?(a) || a.start_with?("--file=") }
      return if args.any? {|a| ["--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l"].include?(a) }

      # Required lazily because this file is loaded in every spawned ruby
      # before RubygemsVersionManager switches RubyGems, where loading extra
      # default gems (pathname, through support/path) breaks the setup.
      require_relative "path"
      dir = File.expand_path(path.to_s)
      tmp_root = Spec::Path.tmp_root.to_s
      return if dir == tmp_root || dir.start_with?(tmp_root + File::SEPARATOR)

      raise "Refusing to run `git #{cmd}` in #{dir}: " \
            "a local git config write outside tmp/ could end up in the checkout's own .git/config"
    end

    def sh(cmd, options = {})
      dir = options[:dir]
      env = options[:env] || {}

      command_execution = CommandExecution.new(cmd.to_s, timeout: options[:timeout] || (Gem.win_platform? ? 120 : 60))

      open3_opts = {}
      open3_opts[:chdir] = dir if dir

      require "open3"
      require "shellwords"
      Open3.popen3(env, *cmd.shellsplit, **open3_opts) do |stdin, stdout, stderr, wait_thr|
        yield stdin, stdout, wait_thr if block_given?
        stdin.close

        stdout_handler = ->(data) { command_execution.original_stdout << data }
        stderr_handler = ->(data) { command_execution.original_stderr << data }

        stdout_thread = read_stream(stdout, stdout_handler, timeout: command_execution.timeout)
        stderr_thread = read_stream(stderr, stderr_handler, timeout: command_execution.timeout)

        stdout_thread.join
        stderr_thread.join

        status = wait_thr.value
        command_execution.exitstatus = if status.exited?
          status.exitstatus
        elsif status.signaled?
          exit_status_for_signal(status.termsig)
        end
      rescue TimeoutExceeded
        command_execution.failure_reason = :timeout
        command_execution.exitstatus = exit_status_for_signal(Signal.list["INT"])
      end

      unless options[:raise_on_error] == false || command_execution.success?
        command_execution.raise_error!
      end

      command_executions << command_execution

      command_execution.stdout
    end

    # Mostly copied from https://github.com/piotrmurach/tty-command/blob/49c37a895ccea107e8b78d20e4cb29de6a1a53c8/lib/tty/command/process_runner.rb#L165-L193
    def read_stream(stream, handler, timeout:)
      Thread.new do
        Thread.current.report_on_exception = false
        cmd_start = Time.now
        readers = [stream]

        while readers.any?
          ready = IO.select(readers, nil, readers, timeout)
          raise TimeoutExceeded if ready.nil?

          ready[0].each do |reader|
            chunk = reader.readpartial(16 * 1024)
            handler.call(chunk)

            # control total time spent reading
            runtime = Time.now - cmd_start
            time_left = timeout - runtime
            raise TimeoutExceeded if time_left < 0.0
          rescue Errno::EAGAIN, Errno::EINTR
          rescue EOFError, Errno::EPIPE, Errno::EIO
            readers.delete(reader)
            reader.close
          end
        end
      end
    end

    def all_commands_output
      return "" if command_executions.empty?

      "\n\nCommands:\n#{command_executions.map(&:to_s_verbose).join("\n\n")}"
    end
  end
end
