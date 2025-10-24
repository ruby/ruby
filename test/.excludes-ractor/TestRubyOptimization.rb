exclude(:test_string_freeze_saves_memory, "ObjectSpace.memsize_of")
exclude(:test_opt_new, "RubyVM::Iseq.compile/eval not working across multiple ractors")
exclude(/tailcall/, "ractor incompatible")
