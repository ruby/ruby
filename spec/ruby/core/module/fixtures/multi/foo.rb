module ModuleSpecs::Autoload
  module Foo
    autoload :Bar, 'foo/bar_baz'
    autoload :Baz, 'foo/bar_baz'
  end
end
