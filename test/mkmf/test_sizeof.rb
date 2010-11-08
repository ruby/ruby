require_relative 'base'

class TestMkmf
  class TestSizeof < TestMkmf
    def test_sizeof
      open("confdefs.h", "w") {|f|
        f.puts "typedef struct {char x;} test1_t;"
      }
      assert_equal(1, mkmf {check_sizeof("test1_t", "confdefs.h")})
    end
  end
end
