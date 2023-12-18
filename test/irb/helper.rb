require "test/unit"
require "pathname"

begin
  require_relative "../lib/helper"
  require_relative "../lib/envutil"
rescue LoadError # ruby/ruby defines helpers differently
end

begin
  require "pty"
rescue LoadError # some platforms don't support PTY
end

module IRB
  class InputMethod; end
end

module TestIRB
  class TestCase < Test::Unit::TestCase
    class TestInputMethod < ::IRB::InputMethod
      attr_reader :list, :line_no

      def initialize(list = [])
        @line_no = 0
        @list = list
      end

      def gets
        @list[@line_no]&.tap {@line_no += 1}
      end

      def eof?
        @line_no >= @list.size
      end

      def encoding
        Encoding.default_external
      end

      def reset
        @line_no = 0
      end
    end

    def ruby_core?
      !Pathname(__dir__).join("../../", "irb.gemspec").exist?
    end

    def save_encodings
      @default_encoding = [Encoding.default_external, Encoding.default_internal]
      @stdio_encodings = [STDIN, STDOUT, STDERR].map {|io| [io.external_encoding, io.internal_encoding] }
    end

    def restore_encodings
      EnvUtil.suppress_warning do
        Encoding.default_external, Encoding.default_internal = *@default_encoding
        [STDIN, STDOUT, STDERR].zip(@stdio_encodings) do |io, encs|
          io.set_encoding(*encs)
        end
      end
    end

    def without_rdoc(&block)
      ::Kernel.send(:alias_method, :irb_original_require, :require)

      ::Kernel.define_method(:require) do |name|
        raise LoadError, "cannot load such file -- rdoc (test)" if name.match?("rdoc") || name.match?(/^rdoc\/.*/)
        ::Kernel.send(:irb_original_require, name)
      end

      yield
    ensure
      EnvUtil.suppress_warning {
        ::Kernel.send(:alias_method, :require, :irb_original_require)
        ::Kernel.undef_method :irb_original_require
      }
    end
  end

  class IntegrationTestCase < TestCase
    LIB = File.expand_path("../../lib", __dir__)
    TIMEOUT_SEC = 3

    def setup
      @envs = {}
      @tmpfiles = []

      unless defined?(PTY)
        omit "Integration tests require PTY."
      end

      if ruby_core?
        omit "This test works only under ruby/irb"
      end

      write_rc <<~RUBY
        IRB.conf[:USE_PAGER] = false
      RUBY
    end

    def teardown
      @tmpfiles.each do |tmpfile|
        File.unlink(tmpfile)
      end
    end

    def run_ruby_file(&block)
      cmd = [EnvUtil.rubybin, "-I", LIB, @ruby_file.to_path]
      tmp_dir = Dir.mktmpdir

      @commands = []
      lines = []

      yield

      # Test should not depend on user's irbrc file
      @envs["HOME"] ||= tmp_dir
      @envs["XDG_CONFIG_HOME"] ||= tmp_dir
      @envs["IRBRC"] = nil unless @envs.key?("IRBRC")

      PTY.spawn(@envs.merge("TERM" => "dumb"), *cmd) do |read, write, pid|
        Timeout.timeout(TIMEOUT_SEC) do
          while line = safe_gets(read)
            lines << line

            # means the breakpoint is triggered
            if line.match?(/binding\.irb/)
              while command = @commands.shift
                write.puts(command)
              end
            end
          end
        end
      ensure
        read.close
        write.close
        kill_safely(pid)
      end

      lines.join
    rescue Timeout::Error
      message = <<~MSG
      Test timedout.

      #{'=' * 30} OUTPUT #{'=' * 30}
        #{lines.map { |l| "  #{l}" }.join}
      #{'=' * 27} END OF OUTPUT #{'=' * 27}
      MSG
      assert_block(message) { false }
    ensure
      FileUtils.remove_entry tmp_dir
    end

    # read.gets could raise exceptions on some platforms
    # https://github.com/ruby/ruby/blob/master/ext/pty/pty.c#L721-L728
    def safe_gets(read)
      read.gets
    rescue Errno::EIO
      nil
    end

    def kill_safely pid
      return if wait_pid pid, TIMEOUT_SEC

      Process.kill :TERM, pid
      return if wait_pid pid, 0.2

      Process.kill :KILL, pid
      Process.waitpid(pid)
    rescue Errno::EPERM, Errno::ESRCH
    end

    def wait_pid pid, sec
      total_sec = 0.0
      wait_sec = 0.001 # 1ms

      while total_sec < sec
        if Process.waitpid(pid, Process::WNOHANG) == pid
          return true
        end
        sleep wait_sec
        total_sec += wait_sec
        wait_sec *= 2
      end

      false
    rescue Errno::ECHILD
      true
    end

    def type(command)
      @commands << command
    end

    def write_ruby(program)
      @ruby_file = Tempfile.create(%w{irb- .rb})
      @tmpfiles << @ruby_file
      @ruby_file.write(program)
      @ruby_file.close
    end

    def write_rc(content)
      # Append irbrc content if a tempfile for it already exists
      if @irbrc
        @irbrc = File.open(@irbrc, "a")
      else
        @irbrc = Tempfile.new('irbrc')
        @tmpfiles << @irbrc
      end

      @irbrc.write(content)
      @irbrc.close
      @envs['IRBRC'] = @irbrc.path
    end
  end
end
