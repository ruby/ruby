# Add Eisel-Lemire algorithm for faster String#to_f

## Summary

This PR adds the Eisel-Lemire algorithm for string-to-float conversion, providing significant performance improvements for `String#to_f`, especially for numbers with many significant digits.

## Performance Results

Benchmark: 3,000,000 iterations per category

| Input Type | Master | This PR | Improvement |
|------------|--------|---------|-------------|
| Simple decimals (`"1.5"`, `"3.14"`) | 0.142s | 0.117s | **17% faster** |
| Prices (`"9.99"`, `"19.95"`) | 0.141s | 0.120s | **15% faster** |
| Small integers (`"5"`, `"42"`) | 0.131s | 0.114s | **13% faster** |
| Math constants (`"3.141592653589793"`) | 0.615s | 0.194s | **3.2x faster** |
| High precision (`"0.123456789012345"`) | 0.504s | 0.190s | **2.7x faster** |
| Scientific (`"1e5"`, `"2e10"`) | 0.140s | 0.139s | ~same |

### Key Insights

- **Simple numbers** (1-6 digits): 13-17% faster via ultra-fast paths
- **Complex numbers** (10+ digits): 2.7-3.2x faster via Eisel-Lemire algorithm
- **No regressions** for any input type

## Implementation Details

### Files Changed

- `object.c` - Added Eisel-Lemire algorithm and fast paths (~320 lines)
- `eisel_lemire_pow5.inc` - Powers of 5 lookup table (651 entries, ~10KB)

### Algorithm Overview

The implementation adds three optimization levels to `rb_cstr_to_dbl_raise`:

1. **Ultra-fast path for small integers** (`try_small_integer_fast_path`)
   - Handles: `"5"`, `"42"`, `"-123"` (up to 3 digits)
   - Simple digit parsing, direct conversion to double

2. **Ultra-fast path for simple decimals** (`try_simple_decimal_fast_path`)
   - Handles: `"1.5"`, `"9.99"`, `"199.95"` (up to 3+3 digits)
   - Parses integer and fractional parts separately
   - Uses precomputed divisors (10, 100, 1000)

3. **Eisel-Lemire algorithm** (`rb_eisel_lemire64`)
   - Handles complex numbers with many significant digits
   - Uses 128-bit multiplication with precomputed powers of 5
   - Falls back to `strtod` for ambiguous rounding cases

### Technical Details

- **128-bit multiplication**: Uses `__uint128_t` when available, falls back to portable 64-bit emulation
- **Powers of 5 table**: 651 precomputed 128-bit values for exponents [-342, 308]
- **Underscore handling**: Proper Ruby underscore validation (between digits only)
- **Fallback**: Falls back to `strtod` for edge cases (hex floats, >19 digits, ambiguous rounding)

## References

- [Eisel-Lemire paper](https://arxiv.org/abs/2101.11408) - "Number Parsing at a Gigabyte per Second" (Software: Practice and Experience, 2021)
- [fast_float C++ library](https://github.com/fastfloat/fast_float)
- [Go implementation](https://github.com/golang/go/blob/master/src/strconv/eisel_lemire.go)
- [Nigel Tao's blog post](https://nigeltao.github.io/blog/2020/eisel-lemire.html) - Excellent explanation of the algorithm

## Test Results

All existing tests pass:

```
487 tests, 27393 assertions, 0 failures, 0 errors, 0 skips
```

Tested specifically:
- `test/ruby/test_float.rb` - All float parsing tests
- `test/ruby/test_string.rb` - All string conversion tests

## Benchmark Script

```ruby
ITERATIONS = 3_000_000

def bench(name, strings)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  (ITERATIONS / strings.size).times { strings.each(&:to_f) }
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  printf "%-35s %0.3fs\n", name, elapsed
end

bench("Simple decimals (1.5, 3.14)",
      %w[1.5 2.0 3.14 99.99 0.5 0.25 10.0 7.5 42.0 100.0])

bench("Prices (9.99, 19.95)",
      %w[9.99 19.95 29.99 49.95 99.99 149.99 199.95 299.99 399.95 499.99])

bench("Small integers (5, 42)",
      %w[5 42 123 7 99 256 1 0 50 999])

bench("Math constants (Pi, E)",
      %w[3.141592653589793 2.718281828459045 1.4142135623730951])

bench("High precision decimals",
      %w[0.123456789012345 9.876543210987654 1.111111111111111])

bench("Scientific (1e5, 2e10)",
      %w[1e5 2e6 3e7 4e8 5e9 1e10])
```

## Why This Matters

Most Ruby applications deal with simple numbers (prices, coordinates, measurements), which benefit from the fast paths. Applications dealing with scientific data or high-precision constants benefit dramatically from the Eisel-Lemire algorithm.

The Eisel-Lemire algorithm is already used in:
- Go standard library (`strconv.ParseFloat`)
- Rust standard library
- .NET Core
- Swift
- Many other modern language runtimes

This PR brings Ruby's float parsing performance in line with these implementations.
