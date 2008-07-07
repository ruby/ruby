# SOAP4R - RPC utility.
# Copyright (C) 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


module SOAP


module RPC
  ServerException = Mapping::MappedException

  def self.defined_methods(obj)
    if obj.is_a?(Module)
      obj.methods - Module.methods
    else
      obj.methods - Object.instance_methods(true)
    end
  end
end


end
