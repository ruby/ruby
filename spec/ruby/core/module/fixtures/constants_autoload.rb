autoload :CSAutoloadA, fixture(__FILE__, 'constants_autoload_a.rb')
autoload :CSAutoloadB, fixture(__FILE__, 'constants_autoload_b.rb')
autoload :CSAutoloadC, fixture(__FILE__, 'constants_autoload_c.rb')
module CSAutoloadD
  autoload :InnerModule, fixture(__FILE__, 'constants_autoload_d.rb')
end
