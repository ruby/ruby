p :foo, {"a": proc do end, b: proc do end}

p :foo, {** proc do end, b: proc do end}

p :foo, {:a => proc do end, b: proc do end}

p :foo, {a: proc do end, b: proc do end}

p :foo, {proc do end => proc do end, b: proc do end}
