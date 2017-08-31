require 'mspec/runner/formatters/dotted'

class FileFormatter < DottedFormatter
  # Unregisters DottedFormatter#before, #after methods and
  # registers #load, #unload, which perform the same duties
  # as #before, #after in DottedFormatter.
  def register
    super

    MSpec.unregister :before,    self
    MSpec.unregister :after,     self

    MSpec.register   :load,      self
    MSpec.register   :unload,    self
  end

  alias_method :load, :before
  alias_method :unload, :after
end
