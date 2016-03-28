require 'test/unit'
require "-test-/float"

class TestFloatExt < Test::Unit::TestCase
  NEXTAFTER_VALUES = [
    -Float::INFINITY,
    -Float::MAX,
    -100.0,
    -1.0-Float::EPSILON,
    -1.0,
    -Float::EPSILON,
    -Float::MIN/2,
    -Math.ldexp(0.5, Float::MIN_EXP - Float::MANT_DIG + 1),
    -0.0,
    0.0,
    Math.ldexp(0.5, Float::MIN_EXP - Float::MANT_DIG + 1),
    Float::MIN/2,
    Float::MIN,
    Float::EPSILON,
    1.0,
    1.0+Float::EPSILON,
    100.0,
    Float::MAX,
    Float::INFINITY,
    Float::NAN
  ]

  test_number = 0
  NEXTAFTER_VALUES.each {|n1|
    NEXTAFTER_VALUES.each {|n2|
      tag = n2.infinite? ? "ruby" : "other"
      test_name = "test_nextafter_#{test_number}_#{tag}_#{n1}_#{n2}"
      test_number += 1
      define_method(test_name) {
        v1 = Bug::Float.missing_nextafter(n1, n2)
        v2 = Bug::Float.system_nextafter(n1, n2)
        assert_kind_of(Float, v1)
        assert_kind_of(Float, v2)
        if v1.nan?
          assert(v2.nan?, "Bug::Float.system_nextafter(#{n1}, #{n2}).nan?")
        else
          assert_equal(v1, v2,
            "Bug::Float.missing_nextafter(#{'%a' % n1}, #{'%a' % n2}) = #{'%a' % v1} != " +
            "#{'%a' % v2} = Bug::Float.system_nextafter(#{'%a' % n1}, #{'%a' % n2})")
          if v1 == 0
            s1 = 1.0/v1 < 0 ? "negative-zero" : "positive-zero"
            s2 = 1.0/v2 < 0 ? "negative-zero" : "positive-zero"
            begin
              assert_equal(s1, s2,
              "Bug::Float.missing_nextafter(#{'%a' % n1}, #{'%a' % n2}) = #{'%a' % v1} != " +
              "#{'%a' % v2} = Bug::Float.system_nextafter(#{'%a' % n1}, #{'%a' % n2})")
            rescue Minitest::Assertion
              if /aix/ =~ RUBY_PLATFORM
                skip "Known bug in nextafter(3) on AIX"
              end
              raise $!
            end
          end
        end
      }
    }
  }

end
