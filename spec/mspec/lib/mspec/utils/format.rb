# If the implementation on which the specs are run cannot
# load pp from the standard library, add a pp.rb file that
# defines the #pretty_inspect method on Object or Kernel.
begin
  require 'pp'
rescue LoadError
  module Kernel
    def pretty_inspect
      inspect
    end
  end
end

module MSpec
  def self.format(obj)
    if String === obj and obj.include?("\n")
      "\n#{obj.inspect.gsub('\n', "\n")}"
    else
      obj.pretty_inspect.chomp
    end
  rescue => e
    "#<#{obj.class}>(#pretty_inspect raised #{e.inspect})"
  end
end
