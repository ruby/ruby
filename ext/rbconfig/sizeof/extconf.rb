# frozen_string_literal: false
$srcs = %w[sizes.c]
$distcleanfiles.concat($srcs)

check_sizeof('int_least8_t')
check_sizeof('int_least16_t')
check_sizeof('int_least32_t')
check_sizeof('int_least64_t')
check_sizeof('int_fast8_t')
check_sizeof('int_fast16_t')
check_sizeof('int_fast32_t')
check_sizeof('int_fast64_t')
check_sizeof('intmax_t')
check_sizeof('sig_atomic_t', %w[signal.h])
check_sizeof('wchar_t')
check_sizeof('wint_t', %w[wctype.h])
check_sizeof('wctrans_t', %w[wctype.h])
check_sizeof('wctype_t', %w[wctype.h])
check_sizeof('_Bool')
check_sizeof('long double')
check_sizeof('float _Complex')
check_sizeof('double _Complex')
check_sizeof('long double _Complex')
check_sizeof('float _Imaginary')
check_sizeof('double _Imaginary')
check_sizeof('long double _Imaginary')
check_sizeof('__int128') # x86_64 ABI (optional)
check_sizeof('__float128') # x86_64 ABI (optional)
check_sizeof('_Decimal32') # x86_64 ABI
check_sizeof('_Decimal64') # x86_64 ABI
check_sizeof('_Decimal128') # x86_64 ABI
check_sizeof('__m64') # x86_64 ABI (optional)
check_sizeof('__m128') # x86_64 ABI (optional)
check_sizeof('__float80') # gcc x86

create_makefile('rbconfig/sizeof')
