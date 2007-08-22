# urn:example.com:simpletype-rpc-type
class Version_struct
  @@schema_type = "version_struct"
  @@schema_ns = "urn:example.com:simpletype-rpc-type"

  attr_accessor :version
  attr_accessor :msg

  def initialize(version = nil, msg = nil)
    @version = version
    @msg = msg
  end
end

# urn:example.com:simpletype-rpc-type
module Versions
  C_16 = "1.6"
  C_18 = "1.8"
  C_19 = "1.9"
end
