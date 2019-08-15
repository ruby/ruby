a = TOPLEVEL_BINDING.object_id
require_relative 'toplevel_binding_id_required'
c = eval('TOPLEVEL_BINDING.object_id')
p [a, $b, c].uniq.size
