$srcs = %w[sizes.c]
$distcleanfiles.concat($srcs)
check_sizeof('__int128')
create_makefile('rbconfig/sizeof')
