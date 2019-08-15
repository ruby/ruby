p TOPLEVEL_BINDING.local_variable_get(:a)
p TOPLEVEL_BINDING.local_variable_get(:b)
a = 1
p TOPLEVEL_BINDING.local_variable_get(:a)
p TOPLEVEL_BINDING.local_variable_get(:b)
b = 2
a = 3
p TOPLEVEL_BINDING.local_variable_get(:a)
p TOPLEVEL_BINDING.local_variable_get(:b)
