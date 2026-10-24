# frozen_string_literal: true

module Spec
  class CommandExecution
    # Under RUBY_BOX, every spawned ruby prints an experimental warning to
    # stderr, breaking specs that assert clean stderr.
    RUBY_BOX_WARNING = Regexp.union(
      /^[^\n]*: warning: Ruby::Box is experimental, and the behavior may change in the future!\n?/,
      %r{^See https://docs\.ruby-lang\.org/\S+ for known issues, etc\.\n?}
    )

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
      string = string.dup.force_encoding(Encoding::UTF_8).scrub.gsub("\r\n", "\n")
      string = string.gsub(RUBY_BOX_WARNING, "") if ruby_box_enabled?
      string.strip
    end

    def ruby_box_enabled?
      defined?(Ruby::Box) && Ruby::Box.enabled?
    end
  end
end
