module Digest
  Foo = nil

  sleep 0.2

  remove_const(:Foo)

  class Foo < Class
  end
end
