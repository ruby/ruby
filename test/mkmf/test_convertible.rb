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
          assert_equal((prefix || signed)+type,
                       mkmf {convertible_int("test1_t", "confdefs.h")})
        end
      end
    end
  end
end
