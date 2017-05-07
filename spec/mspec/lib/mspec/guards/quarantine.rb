require 'mspec/guards/guard'

class QuarantineGuard < SpecGuard
  def match?
    true
  end
end

class Object
  def quarantine!(&block)
    QuarantineGuard.new.run_unless(:quarantine!, &block)
  end
end
