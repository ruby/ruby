$".replace($" | [File.basename(__FILE__), __FILE__])
module EnvUtil
  def rubybin
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
    if defined?(RbConfig.ruby)
      File.join(
        Config::CONFIG["bindir"],
	Config::CONFIG["ruby_install_name"] + Config::CONFIG["EXEEXT"]
                )
    else
      "ruby"
    end
  end
  module_function :rubybin

  def verbose_warning
    class << (stderr = "")
      alias write <<
    end
    stderr, $stderr, verbose, $VERBOSE = $stderr, stderr, $VERBOSE, true
    yield stderr
  ensure
    stderr, $stderr, $VERBOSE = $stderr, stderr, verbose
    return stderr
  end
  module_function :verbose_warning
end

begin
  require 'rbconfig'
rescue LoadError
else
  module RbConfig
    @ruby = EnvUtil.rubybin
    class << self
      undef ruby if defined?(ruby)
      attr_reader :ruby
    end
    dir = File.dirname(ruby)
    name = File.basename(ruby, CONFIG['EXEEXT'])
    CONFIG['bindir'] = dir
    CONFIG['ruby_install_name'] = name
    CONFIG['RUBY_INSTALL_NAME'] = name
  end
end
