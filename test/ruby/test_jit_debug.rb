require_relative 'test_jit'

return unless defined?(TestJIT)
return if ENV.key?('APPVEYOR')
return if ENV.key?('RUBYCI_NICKNAME')
return if ENV['RUBY_DEBUG']&.include?('ci') # ci.rvm.jp
return if /mswin/ =~ RUBY_PLATFORM

class TestJITDebug < TestJIT
  @@test_suites.delete TestJIT if self.respond_to? :on_parallel_worker?

  def setup
    super
    # let `#eval_with_jit` use --mjit-debug
    @mjit_debug = true
  end
end
