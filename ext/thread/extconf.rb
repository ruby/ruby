require 'mkmf'

enable_config('fastthread', true) or exit

if with_config('mem-pools', true)
  $CPPFLAGS << ' -DUSE_MEM_POOLS'
end

create_makefile("thread")
