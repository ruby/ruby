require_relative 'base'

class TestMkmf
  class TestConvertible < TestMkmf
    def test_typeof_builtin
      ["", ["signed ", ""], "unsigned "].each do |signed, prefix|
        %w[short int long].each do |type|
          assert_equal((prefix || signed)+type,
                       mkmf {convertible_int(signed+type)})
        end
      end
    end

    def test_typeof_typedef
      ["", ["signed ", ""], "unsigned "].each do |signed, prefix|
        %w[short int long].each do |type|
          open("confdefs.h", "w") {|f|
            f.puts "typedef #{signed}#{type} test1_t;"
          }
          $defs.clear
          assert_equal((prefix || signed)+type,
                       mkmf {convertible_int("test1_t", "confdefs.h")})
          (u = signed[/^u/]) and u.upcase!
          assert_includes($defs, "-DTYPEOF_TEST1_T="+"#{prefix||signed}#{type}".quote)
          assert_includes($defs, "-DPRI_TEST1T_PREFIX=PRI_#{type.upcase}_PREFIX")
          assert_includes($defs, "-DTEST1T2NUM=#{u}#{type.upcase}2NUM")
          assert_includes($defs, "-DNUM2TEST1T=NUM2#{u}#{type.upcase}")
        end
      end
    end
  end
end
