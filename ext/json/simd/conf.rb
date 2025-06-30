case RbConfig::CONFIG['host_cpu']
when /^(arm|aarch64)/
  # Try to compile a small program using NEON instructions
  if have_header('arm_neon.h') &&
     have_type('uint8x16_t', headers=['arm_neon.h']) && try_compile(<<~'SRC')
      #include <arm_neon.h>
      int main(int argc, char **argv) {
          uint8x16_t test = vdupq_n_u8(32);
          if (argc > 100000) printf("%p", &test);
          return 0;
      }
      SRC
    $defs.push("-DJSON_ENABLE_SIMD")
  end
when /^(x86_64|x64)/
  if have_header('x86intrin.h') &&
     have_type('__m128i', headers=['x86intrin.h']) && try_compile(<<~'SRC')
      #include <x86intrin.h>
      int main(int argc, char **argv) {
          __m128i test = _mm_set1_epi8(32);
          if (argc > 100000) printf("%p", &test);
          return 0;
      }
      SRC
    $defs.push("-DJSON_ENABLE_SIMD")
  end
end

have_header('cpuid.h')
