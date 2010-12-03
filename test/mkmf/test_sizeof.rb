require_relative 'base'

class TestMkmf
  class TestSizeof < TestMkmf
    def test_sizeof_builtin
      %w[char short int long float double void*].each do |type|
        assert_kind_of(Integer, mkmf {check_sizeof(type)})
      end
    end

    def test_sizeof_struct
      open("confdefs.h", "w") {|f|
        f.puts "typedef struct {char x;} test1_t;"
      }
      assert_equal(1, mkmf {check_sizeof("test1_t", "confdefs.h")})
    end
  end
end
