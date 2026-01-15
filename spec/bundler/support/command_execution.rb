# frozen_string_literal: true

module Spec
  class CommandExecution
    def initialize(command, timeout:)
      @command = command
      @timeout = timeout
      @original_stdout = String.new
      @original_stderr = String.new
    end

    attr_accessor :exitstatus, :command, :original_stdout, :original_stderr
    attr_reader :timeout
    attr_writer :failure_reason

    def raise_error!
      return unless failure?

      error_header = if failure_reason == :timeout
        "Invoking `#{command}` was aborted after #{timeout} seconds with output:"
      else
        "Invoking `#{command}` failed with output:"
      end

      raise <<~ERROR
        #{error_header}

        ----------------------------------------------------------------------
        #{stdboth}
        ----------------------------------------------------------------------
      ERROR
    end

    def to_s
      "$ #{command}"
    end
    alias_method :inspect, :to_s

    def stdboth
      @stdboth ||= [stderr, stdout].join("\n").strip
    end

    def stdout
      normalize(original_stdout)
    end

    def stderr
      normalize(original_stderr)
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

    private

    attr_reader :failure_reason

    def normalize(string)
      string.force_encoding(Encoding::UTF_8).strip.gsub("\r\n", "\n")
    end
  end
end
