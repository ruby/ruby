# frozen_string_literal: true

$ns_in_ns = ::Namespace.current

module CurrentNamespace
  def self.in_require
    $ns_in_ns
  end

  def self.in_method_call
    ::Namespace.current
  end
end
