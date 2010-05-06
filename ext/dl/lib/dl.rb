require 'dl.so'

begin
  require 'fiddle'
rescue LoadError
end

module DL
  def self.fiddle?
    Object.const_defined?(:Fiddle)
  end
end
