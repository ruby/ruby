require 'mkmf'

if RUBY_ENGINE == 'truffleruby'
  # The pure-Ruby generator is faster on TruffleRuby, so skip compiling the generator extension
  File.write('Makefile', dummy_makefile("").join)
else
  append_cflags("-std=c99")
  $defs << "-DJSON_GENERATOR"

  if enable_config('generator-use-simd', default=!ENV["JSON_DISABLE_SIMD"])
    if RbConfig::CONFIG['host_cpu'] =~ /^(arm.*|aarch64.*)/
      # Try to compile a small program using NEON instructions
      if have_header('arm_neon.h')
        have_type('uint8x16_t', headers=['arm_neon.h']) && try_compile(<<~'SRC')
          #include <arm_neon.h>
          int main() {
              uint8x16_t test = vdupq_n_u8(32);
              return 0;
          }
        SRC
          $defs.push("-DJSON_ENABLE_SIMD")
      end
    end

    if have_header('x86intrin.h') && have_type('__m128i', headers=['x86intrin.h']) && try_compile(<<~'SRC')
      #include <x86intrin.h>
      int main() {
          __m128i test = _mm_set1_epi8(32);
          return 0;
      }
      SRC
        $defs.push("-DJSON_ENABLE_SIMD")
    end

    have_header('cpuid.h')
  end

  create_makefile 'json/ext/generator'
end
