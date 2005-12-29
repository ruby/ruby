module EnvUtil
  def rubybin
    if ruby = ENV["RUBY"]
      return ruby
    end
    ruby = "ruby"
    3.times do
      if File.exist? ruby or File.exist? ruby+".exe"
        return File.expand_path(ruby)
      end
      ruby = File.join("..", ruby)
    end
    begin
      require "rbconfig"
      File.join(
        Config::CONFIG["bindir"],
	Config::CONFIG["ruby_install_name"] + Config::CONFIG["EXEEXT"]
      )
    rescue LoadError
      "ruby"
    end
  end
  module_function :rubybin
end
