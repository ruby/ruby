require 'dl.so'

begin
  require 'fiddle' unless Object.const_defined?(:Fiddle)
rescue LoadError
end

module DL
  # Returns true if DL is using Fiddle, the libffi wrapper.
  def self.fiddle?
    Object.const_defined?(:Fiddle)
  end
end
