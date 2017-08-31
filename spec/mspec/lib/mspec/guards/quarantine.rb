require 'mspec/guards/guard'

class QuarantineGuard < SpecGuard
  def match?
    true
  end
end

def quarantine!(&block)
  QuarantineGuard.new.run_unless(:quarantine!, &block)
end
