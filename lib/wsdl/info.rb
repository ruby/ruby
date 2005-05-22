# WSDL4R - WSDL information base.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


module WSDL


class Info
  attr_accessor :root
  attr_accessor :parent
  attr_accessor :id

  def initialize
    @root = nil
    @parent = nil
    @id = nil
  end

  def inspect
    if self.respond_to?(:name)
      sprintf("#<%s:0x%x %s>", self.class.name, __id__, self.name)
    else
      sprintf("#<%s:0x%x>", self.class.name, __id__)
    end
  end

  def parse_element(element); end	# abstract
  
  def parse_attr(attr, value); end	# abstract

  def parse_epilogue; end		# abstract
end


end
