# frozen_string_literal: true
require_relative "utils"

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
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      100.times { OpenSSL.fixed_length_secure_compare(a, b) }
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      100.times { OpenSSL.fixed_length_secure_compare(a, c) }
      t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      a_b_time += t2 - t1
      a_c_time += t3 - t2
    end
    assert_operator(a_b_time, :<, a_c_time * 10, "fixed_length_secure_compare timing test failed")
    assert_operator(a_c_time, :<, a_b_time * 10, "fixed_length_secure_compare timing test failed")
  end if ENV["OSSL_TEST_ALL"] == "1"

  def test_error_data
    # X509V3_EXT_nconf_nid() called from OpenSSL::X509::ExtensionFactory#create_ext is a function
    # that uses ERR_raise_data() to append additional information about the error.
    #
    # The generated message should look like:
    #     "subjectAltName = IP:not.a.valid.ip.address: bad ip address (value=not.a.valid.ip.address)"
    #     "subjectAltName = IP:not.a.valid.ip.address: error in extension (name=subjectAltName, value=IP:not.a.valid.ip.address)"
    ef = OpenSSL::X509::ExtensionFactory.new
    assert_raise_with_message(OpenSSL::X509::ExtensionError, /value=(IP:)?not.a.valid.ip.address\)/) {
      ef.create_ext("subjectAltName", "IP:not.a.valid.ip.address")
    }
  end
end

end
