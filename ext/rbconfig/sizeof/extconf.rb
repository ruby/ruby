# frozen_string_literal: false
$srcs = %w[sizes.c limits.c]
$distcleanfiles.concat($srcs)

have_type('int_least8_t')
have_type('int_least16_t')
have_type('int_least32_t')
have_type('int_least64_t')
have_type('int_fast8_t')
have_type('int_fast16_t')
have_type('int_fast32_t')
have_type('int_fast64_t')
have_type('intmax_t')
have_type('sig_atomic_t', %w[signal.h])
have_type('wchar_t')
have_type('wint_t', %w[wctype.h])
have_type('wctrans_t', %w[wctype.h])
have_type('wctype_t', %w[wctype.h])
have_type('_Bool')
have_type('long double')
have_type('float _Complex')
have_type('double _Complex')
have_type('long double _Complex')
have_type('float _Imaginary')
have_type('double _Imaginary')
have_type('long double _Imaginary')
have_type('__int128') # x86_64 ABI (optional)
have_type('__float128') # x86_64 ABI (optional)
have_type('_Decimal32') # x86_64 ABI
have_type('_Decimal64') # x86_64 ABI
have_type('_Decimal128') # x86_64 ABI
have_type('__m64') # x86_64 ABI (optional)
have_type('__m128') # x86_64 ABI (optional)
have_type('__float80') # gcc x86

create_makefile('rbconfig/sizeof')
