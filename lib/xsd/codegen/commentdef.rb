# XSD4R - Generating comment definition code
# Copyright (C) 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/codegen/gensupport'


module XSD
module CodeGen


module CommentDef
  include GenSupport

  attr_accessor :comment

private

  def dump_comment
    if /\A#/ =~ @comment
      format(@comment)
    else
      format(@comment).gsub(/^/, '# ')
    end
  end
end


end
end
