module EnvUtil
  def rubybin
    miniruby = "miniruby"
    3.times do
      if File.exist? miniruby or File.exist? miniruby+".exe"
        return File.expand_path(miniruby)
      end
      miniruby = "../"+miniruby
    end
    "ruby"
  end
  module_function :rubybin
end
