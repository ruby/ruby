module EnvUtil
  def rubybin
    miniruby = "miniruby"
    3.times do
      if File.exist? miniruby or File.exist? miniruby+".exe"
        return File.expand_path(miniruby)
      end
      miniruby = File.join("..", miniruby)
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
