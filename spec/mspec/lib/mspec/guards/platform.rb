require 'mspec/guards/guard'

class PlatformGuard < SpecGuard
  def self.implementation?(*args)
    args.any? do |name|
      case name
      when :rubinius
        RUBY_ENGINE.start_with?('rbx')
      when :ruby, :jruby, :truffleruby, :ironruby, :macruby, :maglev, :topaz, :opal
        RUBY_ENGINE.start_with?(name.to_s)
      else
        raise "unknown implementation #{name}"
      end
    end
  end

  def self.standard?
    implementation? :ruby
  end

  HOST_OS = begin
    require 'rbconfig'
    RbConfig::CONFIG['host_os'] || RUBY_PLATFORM
  rescue LoadError
    RUBY_PLATFORM
  end.downcase

  def self.os?(*oses)
    oses.any? do |os|
      raise ":java is not a valid OS" if os == :java
      if os == :windows
        HOST_OS =~ /(mswin|mingw)/
      else
        HOST_OS.include?(os.to_s)
      end
    end
  end

  def self.windows?
    os?(:windows)
  end

  WORD_SIZE = 1.size * 8

  POINTER_SIZE = begin
    require 'rbconfig/sizeof'
    RbConfig::SIZEOF["void*"] * 8
  rescue LoadError
    WORD_SIZE
  end

  def self.wordsize?(size)
    size == WORD_SIZE
  end

  def self.pointer_size?(size)
    size == POINTER_SIZE
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
      when :wordsize
        match &&= PlatformGuard.wordsize? value
      when :pointer_size
        match &&= PlatformGuard.pointer_size? value
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
