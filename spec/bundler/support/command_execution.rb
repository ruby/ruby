# frozen_string_literal: true

module Spec
  CommandExecution = Struct.new(:command, :working_directory, :exitstatus, :original_stdout, :original_stderr) do
    def to_s
      "$ #{command}"
    end
    alias_method :inspect, :to_s

    def stdboth
      @stdboth ||= [stderr, stdout].join("\n").strip
    end

    def stdout
      original_stdout
    end

    # Can be removed once/if https://github.com/oneclick/rubyinstaller2/pull/369 is resolved
    def stderr
      return original_stderr unless Gem.win_platform?

      original_stderr.split("\n").reject do |l|
        l.include?("operating_system_defaults")
      end.join("\n")
    end

    def to_s_verbose
      [
        to_s,
        stdout,
        stderr,
        exitstatus ? "# $? => #{exitstatus}" : "",
      ].reject(&:empty?).join("\n")
    end

    def success?
      return true unless exitstatus
      exitstatus == 0
    end

    def failure?
      return true unless exitstatus
      exitstatus > 0
    end
  end
end
