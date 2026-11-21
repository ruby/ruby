module DescendantsExt
end

class String
  include DescendantsExt
end

class BoxedString < String
end

MainClass = Ruby::Box.main::TestBoxDescendantsMain

class MainClass
  include DescendantsExt
end

module Descendants
  def self.ext_descendants
    DescendantsExt.descendants
  end

  def self.string_descendants
    String.descendants
  end
end
