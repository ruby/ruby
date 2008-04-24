require "open3"
require "timeout"

module EnvUtil
  def rubybin
    unless ENV["RUBYOPT"]
      
    end
    if ruby = ENV["RUBY"]
      return ruby
    end
    ruby = "ruby"
    rubyexe = ruby+".exe"
    3.times do
      if File.exist? ruby and File.executable? ruby and !File.directory? ruby
        return File.expand_path(ruby)
      end
      if File.exist? rubyexe and File.executable? rubyexe
        return File.expand_path(ruby)
      end
      ruby = File.join("..", ruby)
    end
    begin
      require "rbconfig"
      File.join(
        RbConfig::CONFIG["bindir"],
	RbConfig::CONFIG["ruby_install_name"] + RbConfig::CONFIG["EXEEXT"]
      )
    rescue LoadError
      "ruby"
    end
  end
  module_function :rubybin

  LANG_ENVS = %w"LANG LC_ALL LC_CTYPE"
  def rubyexec(*args)
    if /(mswin|bccwin|mingw|emx)/ =~ RUBY_PLATFORM
      flunk("cannot test in win32")
      return
    end

    ruby = EnvUtil.rubybin
    c = "C"
    env = {}
    LANG_ENVS.each {|lc| env[lc], ENV[lc] = ENV[lc], c}
    stdin = stdout = stderr = nil
    Timeout.timeout(10) do
      stdin, stdout, stderr = Open3.popen3(*([ruby] + args))
      env.each_pair {|lc, v|
        if v
          ENV[lc] = v
        else
          ENV.delete(lc)
        end
      }
      env = nil
      yield(stdin, stdout, stderr)
    end

  ensure
    env.each_pair {|lc, v|
      if v
        ENV[lc] = v
      else
        ENV.delete(lc)
      end
    } if env
    stdin .close unless !stdin  || stdin .closed?
    stdout.close unless !stdout || stdout.closed?
    stderr.close unless !stderr || stderr.closed?
  end
  module_function :rubyexec
end
