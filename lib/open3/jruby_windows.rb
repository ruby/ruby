#
# Custom implementation of Open3.popen{3,2,2e} that uses java.lang.ProcessBuilder rather than pipes and spawns.
#

require 'jruby' # need access to runtime for RubyStatus construction

module Open3

  java_import java.lang.ProcessBuilder
  java_import org.jruby.RubyProcess
  java_import org.jruby.util.ShellLauncher

  def popen3(*cmd, &block)
    if cmd.size > 0 && Hash === cmd[-1]
      opts = cmd.pop
    else
      opts = {}
    end
    processbuilder_run(cmd, opts, io: IO_3, &block)
  end
  module_function :popen3

  IO_3 = proc do |process|
    [process.getOutputStream.to_io, process.getInputStream.to_io, process.getErrorStream.to_io]
  end

  BUILD_2 = proc do |builder|
    builder.redirectError(ProcessBuilder::Redirect::INHERIT)
  end

  IO_2 = proc do |process|
    [process.getOutputStream.to_io, process.getInputStream.to_io]
  end

  def popen2(*cmd, &block)
    if cmd.size > 0 && Hash === cmd[-1]
      opts = cmd.pop
    else
      opts = {}
    end
    processbuilder_run(cmd, opts, build: BUILD_2, io: IO_2, &block)
  end
  module_function :popen2

  BUILD_2E = proc do |builder|
    builder.redirectErrorStream(true)
  end

  def popen2e(*cmd, &block)
    if cmd.size > 0 && Hash === cmd[-1]
      opts = cmd.pop
    else
      opts = {}
    end
    processbuilder_run(cmd, opts, build: BUILD_2E, io: IO_2, &block)
  end
  module_function :popen2e

  def processbuilder_run(cmd, opts, build: nil, io:)
    if Hash === cmd[0]
      env = cmd.shift;
    else
      env = {}
    end

    if cmd.size == 1 && (cmd[0] =~ / / || ShellLauncher.shouldUseShell(cmd[0]))
      cmd = [RbConfig::CONFIG['SHELL'], JRuby::Util::ON_WINDOWS ? '/c' : '-c', cmd[0]]
    end

    builder = ProcessBuilder.new(cmd.to_java(:string))

    builder.directory(java.io.File.new(opts[:chdir] || Dir.pwd))

    environment = builder.environment
    env.each { |k, v| v.nil? ? environment.remove(k) : environment.put(k, v) }

    build.call(builder) if build

    process = builder.start

    pid = org.jruby.util.ShellLauncher.getPidFromProcess(process)

    parent_io = io.call(process)

    parent_io.each {|i| i.sync = true}

    wait_thr = DetachThread.new(pid) { RubyProcess::RubyStatus.newProcessStatus(JRuby.runtime, process.waitFor << 8, pid) }

    result = [*parent_io, wait_thr]

    if defined? yield
      begin
        return yield(*result)
      ensure
        parent_io.each(&:close)
        wait_thr.join
      end
    end

    result
  end
  module_function :processbuilder_run
  class << self
    private :processbuilder_run
  end

  class DetachThread < Thread
    attr_reader :pid

    def initialize(pid)
      super

      @pid = pid
      self[:pid] = pid
    end
  end

end
