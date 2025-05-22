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

  def zjit_supported?
    return @zjit_supported if defined?(@zjit_supported)
    # nil in mswin
    @zjit_supported = ![nil, 'no'].include?(RbConfig::CONFIG['ZJIT_SUPPORT'])
  end
end
