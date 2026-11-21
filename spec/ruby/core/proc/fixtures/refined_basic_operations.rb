# Refines basic operations like operators and element access,
# including Hash#[] with a String key, so specs can check
# the specialized call paths implementations use for them.
# Do this in a subprocess to not disable optimizations globally for the main process.
module Operators
  refine Integer do
    def +(other)
      "plus(#{self},#{other})"
    end

    def <(other)
      "lt"
    end
  end

  refine Array do
    def [](i)
      "at#{i}"
    end
  end

  refine Hash do
    def [](k)
      "aref(#{k})"
    end
  end
end

refined = -> a, b { [a + b, a < b] }.refined(Operators)
puts refined.call(1, 2)
puts -> a { a[0] }.refined(Operators).call([9])
puts -> h { h["x"] }.refined(Operators).call({ "x" => 1 })
puts -> a, b { a + b }.call(1, 2)
