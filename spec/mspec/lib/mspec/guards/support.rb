require 'mspec/guards/platform'

class SupportedGuard < SpecGuard
  def match?
    if @parameters.include? :ruby
      raise Exception, "improper use of not_supported_on guard"
    end
    !PlatformGuard.standard? and PlatformGuard.implementation?(*@parameters)
  end
end

def not_supported_on(*args, &block)
  SupportedGuard.new(*args).run_unless(:not_supported_on, &block)
end
