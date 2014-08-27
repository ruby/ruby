$srcs = %w[sizes.c]
$distcleanfiles.concat($srcs)
create_makefile('rbconfig/sizeof')
