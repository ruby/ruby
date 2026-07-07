# -*- coding: us-ascii -*-
# frozen_string_literal: false

require "mkmf"

# BLAKE3 build configuration.
#
# The binding is always built from the portable C code (blake3.c,
# blake3_dispatch.c, blake3_portable.c).  On architectures BLAKE3 ships
# optimized backends for, we additionally compile the SIMD implementations
# and let blake3_dispatch.c select the fastest one supported by the CPU the
# program is actually running on (via CPUID on x86).  This means a binary
# built on an AVX-512-capable machine still runs correctly on an older CPU.
#
# Each SIMD translation unit must be compiled with its own instruction-set
# flag, which a single global $CFLAGS can't express, so we emit one explicit
# object rule per backend at the end (see below).  Any x86 backend we do NOT
# compile is disabled with -DBLAKE3_NO_<ISA>; that macro is honoured both by
# the dispatcher and by sibling backends (e.g. blake3_avx2.c falls back to
# SSE4.1 helpers), keeping the set of referenced symbols consistent.

objs = %w[blake3init blake3 blake3_dispatch blake3_portable]

# Extra per-object compiler flags, keyed by object basename.
simd_cflags = {}

# Probe used to confirm the compiler both accepts +flag+ and can compile the
# intrinsics the backend relies on.
def blake3_have_isa?(name, flag, snippet)
  checking_for("#{name} intrinsics (#{flag})") do
    try_compile(snippet, flag)
  end
end

case RbConfig::CONFIG["host_cpu"]
when /\A(x86_64|amd64|x64)\z/i
  # Try to detect which SIMD features this x86 machine and compiler has
  x86_backends = [
    ["blake3_sse2",   "SSE2",    "-msse2",
     "#include <immintrin.h>\nint main(void){ volatile __m128i x = _mm_setzero_si128(); (void)x; return 0; }\n",
     "BLAKE3_NO_SSE2"],
    ["blake3_sse41",  "SSE4.1",  "-msse4.1",
     "#include <immintrin.h>\nint main(void){ volatile __m128i x = _mm_setzero_si128(); return _mm_testz_si128(x, x); }\n",
     "BLAKE3_NO_SSE41"],
    ["blake3_avx2",   "AVX2",    "-mavx2",
     "#include <immintrin.h>\nint main(void){ volatile __m256i x = _mm256_setzero_si256(); (void)x; return 0; }\n",
     "BLAKE3_NO_AVX2"],
    ["blake3_avx512", "AVX-512", "-mavx512f -mavx512vl",
     "#include <immintrin.h>\nint main(void){ volatile __m512i x = _mm512_setzero_si512(); (void)x; return 0; }\n",
     "BLAKE3_NO_AVX512"],
  ]

  x86_backends.each do |obj, name, flag, snippet, no_macro|
    if blake3_have_isa?(name, flag, snippet)
      objs << obj
      simd_cflags[obj] = flag
    else
      $defs << "-D#{no_macro}"
    end
  end
when /\A(aarch64|arm64)\z/i
  # NEON is part of the AArch64 baseline, so no runtime detection or special
  # compiler flag is needed.  Leave BLAKE3_USE_NEON to auto-detect, which is
  # 1 on little-endian AArch64 (see blake3_impl.h).
  objs << "blake3_neon"
else
  # No optimized backend wired up for this architecture (e.g. 32-bit x86,
  # ppc): build portable-only.  Disabling every x86 ISA keeps the dispatcher
  # from referencing backends we didn't compile, and NEON is forced off.
  $defs << "-DBLAKE3_NO_SSE2"
  $defs << "-DBLAKE3_NO_SSE41"
  $defs << "-DBLAKE3_NO_AVX2"
  $defs << "-DBLAKE3_NO_AVX512"
  $defs << "-DBLAKE3_USE_NEON=0"
end

$objs = objs.map { |o| "#{o}.#{$OBJEXT}" }

have_header("sys/cdefs.h")

$preload = %w[digest]

create_makefile("digest/blake3")
