module EnvUtil
  def rubybin
    if File.exist? "miniruby" or File.exist? "miniruby.exe"
      "./miniruby"
    else
      "ruby"
    end
  end
  module_function :rubybin
end
