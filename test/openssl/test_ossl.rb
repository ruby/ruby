# frozen_string_literal: true
require_relative "utils"

require 'benchmark'

if defined?(OpenSSL)

class OpenSSL::OSSL < OpenSSL::SSLTestCase
  def test_fixed_length_secure_compare
    assert_raise(ArgumentError) { OpenSSL.fixed_length_secure_compare("aaa", "a") }
    assert_raise(ArgumentError) { OpenSSL.fixed_length_secure_compare("aaa", "aa") }

    assert OpenSSL.fixed_length_secure_compare("aaa", "aaa")
    assert OpenSSL.fixed_length_secure_compare(
      OpenSSL::Digest.digest('SHA256', "aaa"), OpenSSL::Digest::SHA256.digest("aaa")
    )

    assert_raise(ArgumentError) { OpenSSL.fixed_length_secure_compare("aaa", "aaaa") }
    refute OpenSSL.fixed_length_secure_compare("aaa", "baa")
    refute OpenSSL.fixed_length_secure_compare("aaa", "aba")
    refute OpenSSL.fixed_length_secure_compare("aaa", "aab")
    assert_raise(ArgumentError) { OpenSSL.fixed_length_secure_compare("aaa", "aaab") }
    assert_raise(ArgumentError) { OpenSSL.fixed_length_secure_compare("aaa", "b") }
    assert_raise(ArgumentError) { OpenSSL.fixed_length_secure_compare("aaa", "bb") }
    refute OpenSSL.fixed_length_secure_compare("aaa", "bbb")
    assert_raise(ArgumentError) { OpenSSL.fixed_length_secure_compare("aaa", "bbbb") }
  end

  def test_secure_compare
    refute OpenSSL.secure_compare("aaa", "a")
    refute OpenSSL.secure_compare("aaa", "aa")

    assert OpenSSL.secure_compare("aaa", "aaa")

    refute OpenSSL.secure_compare("aaa", "aaaa")
    refute OpenSSL.secure_compare("aaa", "baa")
    refute OpenSSL.secure_compare("aaa", "aba")
    refute OpenSSL.secure_compare("aaa", "aab")
    refute OpenSSL.secure_compare("aaa", "aaab")
    refute OpenSSL.secure_compare("aaa", "b")
    refute OpenSSL.secure_compare("aaa", "bb")
    refute OpenSSL.secure_compare("aaa", "bbb")
    refute OpenSSL.secure_compare("aaa", "bbbb")
  end

  def test_memcmp_timing
    # Ensure using fixed_length_secure_compare takes almost exactly the same amount of time to compare two different strings.
    # Regular string comparison will short-circuit on the first non-matching character, failing this test.
    # NOTE: this test may be susceptible to noise if the system running the tests is otherwise under load.
    a = "x" * 512_000
    b = "#{a}y"
    c = "y#{a}"
    a = "#{a}x"

    a_b_time = a_c_time = 0
    100.times do
      a_b_time += Benchmark.measure { 100.times { OpenSSL.fixed_length_secure_compare(a, b) } }.real
      a_c_time += Benchmark.measure { 100.times { OpenSSL.fixed_length_secure_compare(a, c) } }.real
    end
    assert_operator(a_b_time, :<, a_c_time * 10, "fixed_length_secure_compare timing test failed")
    assert_operator(a_c_time, :<, a_b_time * 10, "fixed_length_secure_compare timing test failed")
  end
end

end
