main_script = 1
require_relative 'toplevel_binding_variables_required'
eval('eval_var = 3')
p TOPLEVEL_BINDING.local_variables
