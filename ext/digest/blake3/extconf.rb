# -*- coding: us-ascii -*-
# frozen_string_literal: false

require "mkmf"

# Build the portable (no-SIMD) BLAKE3 implementation: only blake3.c,
# blake3_dispatch.c and blake3_portable.c are compiled.  The SIMD
# backends (SSE2/SSE4.1/AVX2/AVX512/NEON) are intentionally left out to
# keep the build simple and dependency-free.  Each instruction set has
# to be disabled explicitly, otherwise blake3_dispatch.c references
# symbols from the omitted backends.  In particular NEON auto-enables on
# AArch64 (see blake3_impl.h), so BLAKE3_USE_NEON must be forced off too.
$defs << "-DBLAKE3_NO_SSE2"
$defs << "-DBLAKE3_NO_SSE41"
$defs << "-DBLAKE3_NO_AVX2"
$defs << "-DBLAKE3_NO_AVX512"
$defs << "-DBLAKE3_USE_NEON=0"

$objs = %w[blake3init blake3 blake3_dispatch blake3_portable].map do |o|
  "#{o}.#{$OBJEXT}"
end

have_header("sys/cdefs.h")

$preload = %w[digest]

create_makefile("digest/blake3")
