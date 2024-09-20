require 'mspec/guards/guard'

class PlatformGuard < SpecGuard
  def self.implementation?(*args)
    args.any? do |name|
      case name
      when :rubinius
        RUBY_ENGINE.start_with?('rbx')
      else
        RUBY_ENGINE.start_with?(name.to_s)
      end
    end
  end

  def self.standard?
    implementation? :ruby
  end

  PLATFORM = if RUBY_ENGINE == "jruby"
    require 'rbconfig'
    "#{RbConfig::CONFIG['host_cpu']}-#{RbConfig::CONFIG['host_os']}"
  else
    RUBY_PLATFORM
  end

  def self.os?(*oses)
    oses.any? do |os|
      raise ":java is not a valid OS" if os == :java
      case os
      when :windows
        PLATFORM =~ /(mswin|mingw)/
      when :wsl
        wsl?
      else
        PLATFORM.include?(os.to_s)
      end
    end
  end

  def self.windows?
    os?(:windows)
  end

  def self.wasi?
    os?(:wasi)
  end

  def self.wsl?
    if defined?(@wsl_p)
      @wsl_p
    else
      @wsl_p = `uname -r`.match?(/microsoft/i)
    end
  end

  POINTER_SIZE = begin
    require 'rbconfig/sizeof'
    RbConfig::SIZEOF["void*"] * 8
  rescue LoadError
    [0].pack('j').size
  end

  C_LONG_SIZE = if defined?(RbConfig::SIZEOF[])
    RbConfig::SIZEOF["long"] * 8
  else
    [0].pack('l!').size
  end

  def self.pointer_size?(size)
    size == POINTER_SIZE
  end

  def self.c_long_size?(size)
    size == C_LONG_SIZE
  end

  def initialize(*args)
    if args.last.is_a?(Hash)
      @options, @platforms = args.last, args[0..-2]
    else
      @options, @platforms = {}, args
    end
    @parameters = args
  end

  def match?
    match = @platforms.empty? ? true : PlatformGuard.os?(*@platforms)
    @options.each do |key, value|
      case key
      when :os
        match &&= PlatformGuard.os?(*value)
      when :pointer_size
        match &&= PlatformGuard.pointer_size? value
      when :c_long_size
        match &&= PlatformGuard::c_long_size? value
      end
    end
    match
  end
end

def platform_is(*args, &block)
  PlatformGuard.new(*args).run_if(:platform_is, &block)
end

def platform_is_not(*args, &block)
  PlatformGuard.new(*args).run_unless(:platform_is_not, &block)
end
