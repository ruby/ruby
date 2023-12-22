require 'rbconfig'

module JITSupport
  module_function

  def yjit_supported?
    return @yjit_supported if defined?(@yjit_supported)
    # nil in mswin
    @yjit_supported = ![nil, 'no'].include?(RbConfig::CONFIG['YJIT_SUPPORT'])
  end

  def yjit_enabled?
    defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled?
  end

  def yjit_force_enabled?
    "#{RbConfig::CONFIG['CFLAGS']} #{RbConfig::CONFIG['CPPFLAGS']}".match?(/(\A|\s)-D ?YJIT_FORCE_ENABLE\b/)
  end

  def rjit_supported?
    return @rjit_supported if defined?(@rjit_supported)
    # nil in mswin
    @rjit_supported = ![nil, 'no'].include?(RbConfig::CONFIG['RJIT_SUPPORT'])
  end

  def rjit_enabled?
    defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?
  end

  def rjit_force_enabled?
    "#{RbConfig::CONFIG['CFLAGS']} #{RbConfig::CONFIG['CPPFLAGS']}".match?(/(\A|\s)-D ?RJIT_FORCE_ENABLE\b/)
  end
end
