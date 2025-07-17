case RbConfig::CONFIG['host_cpu']
when /^(arm|aarch64)/
  # Try to compile a small program using NEON instructions
  header, type, init = 'arm_neon.h', 'uint8x16_t', 'vdupq_n_u8(32)'
when /^(x86_64|x64)/
  header, type, init = 'x86intrin.h', '__m128i', '_mm_set1_epi8(32)'
end
if header
  have_header(header) && try_compile(<<~SRC)
    #{cpp_include(header)}
    int main(int argc, char **argv) {
      #{type} test = #{init};
      if (argc > 100000) printf("%p", &test);
      return 0;
    }
  SRC
  $defs.push("-DJSON_ENABLE_SIMD")
end

have_header('cpuid.h')
