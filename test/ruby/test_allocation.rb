# frozen_string_literal: false
require 'test/unit'

class TestAllocation < Test::Unit::TestCase
  def check_allocations(checks)
    assert_separately([], <<~RUBY)
      $allocations = [0, 0]
      $counts = {}
      failures = []

      def self.num_allocations
        ObjectSpace.count_objects($counts)
        arrays = $counts[:T_ARRAY]
        hashes = $counts[:T_HASH]
        yield
        ObjectSpace.count_objects($counts)
        arrays -= $counts[:T_ARRAY]
        hashes -= $counts[:T_HASH]
        $allocations[0] = -arrays
        $allocations[1] = -hashes
      end

      define_singleton_method(:check_allocations) do |num_arrays, num_hashes, check_code|
        instance_eval <<~RB
          empty_array = empty_array = []
          empty_hash = empty_hash = {}
          array1 = array1 = [1]
          r2k_array = r2k_array = [Hash.ruby2_keywords_hash(a: 3)]
          r2k_array1 = r2k_array1 = [1, Hash.ruby2_keywords_hash(a: 3)]
          r2k_empty_array = r2k_empty_array = [Hash.ruby2_keywords_hash({})]
          r2k_empty_array1 = r2k_empty_array1 = [1, Hash.ruby2_keywords_hash({})]
          hash1 = hash1 = {a: 2}
          nill = nill = nil
          block = block = lambda{}

          num_allocations do
            \#{check_code}
          end
        RB

        if num_arrays != $allocations[0]
          failures << "Expected \#{num_arrays} array allocations for \#{check_code.inspect}, but \#{$allocations[0]} arrays allocated"
        end
        if num_hashes != $allocations[1]
          failures << "Expected \#{num_hashes} hash allocations for \#{check_code.inspect}, but \#{$allocations[1]} hashes allocated"
        end
      end

      GC.start
      GC.disable

      #{checks}

      unless failures.empty?
        assert_equal(true, false, failures.join("\n"))
      end
    RUBY
  end

  class Literal < self
    def test_array_literal
      check_allocations(<<~RUBY)
        check_allocations(1, 0, "[]")
        check_allocations(1, 0, "[1]")
        check_allocations(1, 0, "[*empty_array]")
        check_allocations(1, 0, "[*empty_array, 1, *empty_array]")
        check_allocations(1, 0, "[*empty_array, *empty_array]")
        check_allocations(1, 0, "[#{'1,'*100000}]")
      RUBY
    end

    def test_hash_literal
      check_allocations(<<~RUBY)
        check_allocations(0, 1, "{}")
        check_allocations(0, 1, "{a: 1}")
        check_allocations(0, 1, "{**empty_hash}")
        check_allocations(0, 1, "{**empty_hash, a: 1, **empty_hash}")
        check_allocations(0, 1, "{**empty_hash, **empty_hash}")
        check_allocations(0, 1, "{#{100000.times.map{|i| "a#{i}: 1"}.join(',')}}")
      RUBY
    end
  end

  class MethodCall < self
    def block
      ''
    end

    def test_no_parameters
      only_block = block.empty? ? block : block[2..]
      check_allocations(<<~RUBY)
        def self.none(#{only_block}); end

        check_allocations(0, 0, "none(#{only_block})")
        check_allocations(0, 0, "none(*empty_array#{block})")
        check_allocations(0, 0, "none(**empty_hash#{block})")
        check_allocations(0, 0, "none(*empty_array, **empty_hash#{block})")

        check_allocations(1, 0, "none(*empty_array, *empty_array#{block})")
        check_allocations(0, 1, "none(**empty_hash, **empty_hash#{block})")
        check_allocations(1, 1, "none(*empty_array, *empty_array, **empty_hash, **empty_hash#{block})")

        check_allocations(0, 0, "none(*r2k_empty_array#{block})")
      RUBY
    end

    def test_required_parameter
      check_allocations(<<~RUBY)
        def self.required(x#{block}); end

        check_allocations(0, 0, "required(1#{block})")
        check_allocations(0, 0, "required(1, *empty_array#{block})")
        check_allocations(0, 0, "required(1, **empty_hash#{block})")
        check_allocations(0, 0, "required(1, *empty_array, **empty_hash#{block})")

        check_allocations(0, 0, "required(*array1#{block})")
        check_allocations(0, 1, "required(**hash1#{block})")

        check_allocations(1, 0, "required(*array1, *empty_array#{block})")
        check_allocations(0, 1, "required(**hash1, **empty_hash#{block})")
        check_allocations(1, 0, "required(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(0, 0, "required(*r2k_empty_array1#{block})")
        check_allocations(0, 1, "required(*r2k_array#{block})")

        # Currently allocates 1 array unnecessarily due to splatarray true
        check_allocations(1, 1, "required(*empty_array, **hash1, **empty_hash#{block})")
      RUBY
    end

    def test_optional_parameter
      check_allocations(<<~RUBY)
        def self.optional(x=nil#{block}); end

        check_allocations(0, 0, "optional(1#{block})")
        check_allocations(0, 0, "optional(1, *empty_array#{block})")
        check_allocations(0, 0, "optional(1, **empty_hash#{block})")
        check_allocations(0, 0, "optional(1, *empty_array, **empty_hash#{block})")

        check_allocations(0, 0, "optional(*array1#{block})")
        check_allocations(0, 1, "optional(**hash1#{block})")

        check_allocations(1, 0, "optional(*array1, *empty_array#{block})")
        check_allocations(0, 1, "optional(**hash1, **empty_hash#{block})")
        check_allocations(1, 0, "optional(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(0, 0, "optional(*r2k_empty_array#{block})")
        check_allocations(0, 0, "optional(*r2k_empty_array1#{block})")
        check_allocations(0, 1, "optional(*r2k_array#{block})")

        # Currently allocates 1 array unnecessarily due to splatarray true
        check_allocations(1, 1, "optional(*empty_array, **hash1, **empty_hash#{block})")
      RUBY
    end

    def test_positional_splat_parameter
      check_allocations(<<~RUBY)
        def self.splat(*x#{block}); end

        check_allocations(1, 0, "splat(1#{block})")
        check_allocations(1, 0, "splat(1, *empty_array#{block})")
        check_allocations(1, 0, "splat(1, **empty_hash#{block})")
        check_allocations(1, 0, "splat(1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 0, "splat(*array1#{block})")
        check_allocations(1, 0, "splat(*array1, *empty_array#{block})")
        check_allocations(1, 0, "splat(*array1, **empty_hash#{block})")
        check_allocations(1, 0, "splat(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 0, "splat(1, *array1#{block})")
        check_allocations(1, 0, "splat(1, *array1, *empty_array#{block})")
        check_allocations(1, 0, "splat(1, *array1, **empty_hash#{block})")
        check_allocations(1, 0, "splat(1, *array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 0, "splat(*array1#{block})")
        check_allocations(1, 1, "splat(**hash1#{block})")

        check_allocations(1, 0, "splat(*array1, *empty_array#{block})")
        check_allocations(1, 1, "splat(**hash1, **empty_hash#{block})")
        check_allocations(1, 0, "splat(*array1, *empty_array, **empty_hash#{block})")
        check_allocations(1, 1, "splat(*empty_array, **hash1, **empty_hash#{block})")

        check_allocations(1, 0, "splat(*r2k_empty_array#{block})")
        check_allocations(1, 0, "splat(*r2k_empty_array1#{block})")
        check_allocations(1, 1, "splat(*r2k_array#{block})")
        check_allocations(1, 1, "splat(*r2k_array1#{block})")
      RUBY
    end

    def test_required_and_positional_splat_parameters
      check_allocations(<<~RUBY)
        def self.req_splat(x, *y#{block}); end

        check_allocations(1, 0, "req_splat(1#{block})")
        check_allocations(1, 0, "req_splat(1, *empty_array#{block})")
        check_allocations(1, 0, "req_splat(1, **empty_hash#{block})")
        check_allocations(1, 0, "req_splat(1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 0, "req_splat(*array1#{block})")
        check_allocations(1, 0, "req_splat(*array1, *empty_array#{block})")
        check_allocations(1, 0, "req_splat(*array1, **empty_hash#{block})")
        check_allocations(1, 0, "req_splat(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 0, "req_splat(1, *array1#{block})")
        check_allocations(1, 0, "req_splat(1, *array1, *empty_array#{block})")
        check_allocations(1, 0, "req_splat(1, *array1, **empty_hash#{block})")
        check_allocations(1, 0, "req_splat(1, *array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 0, "req_splat(*array1#{block})")
        check_allocations(1, 1, "req_splat(**hash1#{block})")

        check_allocations(1, 0, "req_splat(*array1, *empty_array#{block})")
        check_allocations(1, 1, "req_splat(**hash1, **empty_hash#{block})")
        check_allocations(1, 0, "req_splat(*array1, *empty_array, **empty_hash#{block})")
        check_allocations(1, 1, "req_splat(*empty_array, **hash1, **empty_hash#{block})")

        check_allocations(1, 0, "req_splat(*r2k_empty_array1#{block})")
        check_allocations(1, 1, "req_splat(*r2k_array#{block})")
        check_allocations(1, 1, "req_splat(*r2k_array1#{block})")
      RUBY
    end

    def test_positional_splat_and_post_parameters
      check_allocations(<<~RUBY)
        def self.splat_post(*x, y#{block}); end

        check_allocations(1, 0, "splat_post(1#{block})")
        check_allocations(1, 0, "splat_post(1, *empty_array#{block})")
        check_allocations(1, 0, "splat_post(1, **empty_hash#{block})")
        check_allocations(1, 0, "splat_post(1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 0, "splat_post(*array1#{block})")
        check_allocations(1, 0, "splat_post(*array1, *empty_array#{block})")
        check_allocations(1, 0, "splat_post(*array1, **empty_hash#{block})")
        check_allocations(1, 0, "splat_post(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 0, "splat_post(1, *array1#{block})")
        check_allocations(1, 0, "splat_post(1, *array1, *empty_array#{block})")
        check_allocations(1, 0, "splat_post(1, *array1, **empty_hash#{block})")
        check_allocations(1, 0, "splat_post(1, *array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 0, "splat_post(*array1#{block})")
        check_allocations(1, 1, "splat_post(**hash1#{block})")

        check_allocations(1, 0, "splat_post(*array1, *empty_array#{block})")
        check_allocations(1, 1, "splat_post(**hash1, **empty_hash#{block})")
        check_allocations(1, 0, "splat_post(*array1, *empty_array, **empty_hash#{block})")
        check_allocations(1, 1, "splat_post(*empty_array, **hash1, **empty_hash#{block})")

        check_allocations(1, 0, "splat_post(*r2k_empty_array1#{block})")
        check_allocations(1, 1, "splat_post(*r2k_array#{block})")
        check_allocations(1, 1, "splat_post(*r2k_array1#{block})")
      RUBY
    end

    def test_keyword_parameter
      check_allocations(<<~RUBY)
        def self.keyword(a: nil#{block}); end

        check_allocations(0, 0, "keyword(a: 2#{block})")
        check_allocations(0, 0, "keyword(*empty_array, a: 2#{block})")
        check_allocations(0, 1, "keyword(a:2, **empty_hash#{block})")
        check_allocations(0, 1, "keyword(**empty_hash, a: 2#{block})")

        check_allocations(0, 0, "keyword(**nil#{block})")
        check_allocations(0, 0, "keyword(**empty_hash#{block})")
        check_allocations(0, 0, "keyword(**hash1#{block})")
        check_allocations(0, 0, "keyword(*empty_array, **hash1#{block})")
        check_allocations(0, 1, "keyword(**hash1, **empty_hash#{block})")
        check_allocations(0, 1, "keyword(**empty_hash, **hash1#{block})")

        check_allocations(0, 0, "keyword(*empty_array#{block})")
        check_allocations(0, 1, "keyword(**hash1, **empty_hash#{block})")
        check_allocations(1, 0, "keyword(*empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(0, 0, "keyword(*empty_array#{block})")
        check_allocations(0, 1, "keyword(**hash1, **empty_hash#{block})")
        check_allocations(1, 0, "keyword(*empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(1, 0, "keyword(*r2k_empty_array#{block})")
        check_allocations(1, 1, "keyword(*r2k_array#{block})")

        # Currently allocates 1 array unnecessarily due to splatarray true
        check_allocations(1, 1, "keyword(*empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "keyword(*empty_array, **hash1, **empty_hash#{block})")
      RUBY
    end

    def test_keyword_splat_parameter
      check_allocations(<<~RUBY)
        def self.keyword_splat(**kw#{block}); end

        check_allocations(0, 1, "keyword_splat(a: 2#{block})")
        check_allocations(0, 1, "keyword_splat(*empty_array, a: 2#{block})")
        check_allocations(0, 1, "keyword_splat(a:2, **empty_hash#{block})")
        check_allocations(0, 1, "keyword_splat(**empty_hash, a: 2#{block})")

        check_allocations(0, 1, "keyword_splat(**nil#{block})")
        check_allocations(0, 1, "keyword_splat(**empty_hash#{block})")
        check_allocations(0, 1, "keyword_splat(**hash1#{block})")
        check_allocations(0, 1, "keyword_splat(*empty_array, **hash1#{block})")
        check_allocations(0, 1, "keyword_splat(**hash1, **empty_hash#{block})")
        check_allocations(0, 1, "keyword_splat(**empty_hash, **hash1#{block})")

        check_allocations(0, 1, "keyword_splat(*empty_array#{block})")
        check_allocations(0, 1, "keyword_splat(**hash1, **empty_hash#{block})")
        check_allocations(1, 1, "keyword_splat(*empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(0, 1, "keyword_splat(*empty_array#{block})")
        check_allocations(0, 1, "keyword_splat(**hash1, **empty_hash#{block})")
        check_allocations(1, 1, "keyword_splat(*empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(1, 1, "keyword_splat(*r2k_empty_array#{block})")
        check_allocations(1, 1, "keyword_splat(*r2k_array#{block})")

        # Currently allocates 1 array unnecessarily due to splatarray true
        check_allocations(1, 1, "keyword_splat(*empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "keyword_splat(*empty_array, **hash1, **empty_hash#{block})")
      RUBY
    end

    def test_keyword_and_keyword_splat_parameter
      check_allocations(<<~RUBY)
        def self.keyword_and_keyword_splat(a: 1, **kw#{block}); end

        check_allocations(0, 1, "keyword_and_keyword_splat(a: 2#{block})")
        check_allocations(0, 1, "keyword_and_keyword_splat(*empty_array, a: 2#{block})")
        check_allocations(0, 1, "keyword_and_keyword_splat(a:2, **empty_hash#{block})")
        check_allocations(0, 1, "keyword_and_keyword_splat(**empty_hash, a: 2#{block})")

        check_allocations(0, 1, "keyword_and_keyword_splat(**nil#{block})")
        check_allocations(0, 1, "keyword_and_keyword_splat(**empty_hash#{block})")
        check_allocations(0, 1, "keyword_and_keyword_splat(**hash1#{block})")
        check_allocations(0, 1, "keyword_and_keyword_splat(*empty_array, **hash1#{block})")
        check_allocations(0, 1, "keyword_and_keyword_splat(**hash1, **empty_hash#{block})")
        check_allocations(0, 1, "keyword_and_keyword_splat(**empty_hash, **hash1#{block})")

        check_allocations(0, 1, "keyword_and_keyword_splat(*empty_array#{block})")
        check_allocations(0, 1, "keyword_and_keyword_splat(**hash1, **empty_hash#{block})")
        check_allocations(1, 1, "keyword_and_keyword_splat(*empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(0, 1, "keyword_and_keyword_splat(*empty_array#{block})")
        check_allocations(0, 1, "keyword_and_keyword_splat(**hash1, **empty_hash#{block})")
        check_allocations(1, 1, "keyword_and_keyword_splat(*empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(1, 1, "keyword_and_keyword_splat(*r2k_empty_array#{block})")
        check_allocations(1, 1, "keyword_and_keyword_splat(*r2k_array#{block})")

        # Currently allocates 1 array unnecessarily due to splatarray true
        check_allocations(1, 1, "keyword_and_keyword_splat(*empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "keyword_and_keyword_splat(*empty_array, **hash1, **empty_hash#{block})")
      RUBY
    end

    def test_required_positional_and_keyword_parameter
      check_allocations(<<~RUBY)
        def self.required_and_keyword(b, a: nil#{block}); end

        check_allocations(0, 0, "required_and_keyword(1, a: 2#{block})")
        check_allocations(0, 0, "required_and_keyword(1, *empty_array, a: 2#{block})")
        check_allocations(0, 1, "required_and_keyword(1, a:2, **empty_hash#{block})")
        check_allocations(0, 1, "required_and_keyword(1, **empty_hash, a: 2#{block})")

        check_allocations(0, 0, "required_and_keyword(1, **nil#{block})")
        check_allocations(0, 0, "required_and_keyword(1, **empty_hash#{block})")
        check_allocations(0, 0, "required_and_keyword(1, **hash1#{block})")
        check_allocations(0, 0, "required_and_keyword(1, *empty_array, **hash1#{block})")
        check_allocations(0, 1, "required_and_keyword(1, **hash1, **empty_hash#{block})")
        check_allocations(0, 1, "required_and_keyword(1, **empty_hash, **hash1#{block})")

        check_allocations(0, 0, "required_and_keyword(1, *empty_array#{block})")
        check_allocations(0, 1, "required_and_keyword(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 0, "required_and_keyword(1, *empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(0, 0, "required_and_keyword(*array1, a: 2#{block})")

        check_allocations(0, 0, "required_and_keyword(*array1, **nill#{block})")
        check_allocations(0, 0, "required_and_keyword(*array1, **empty_hash#{block})")
        check_allocations(0, 0, "required_and_keyword(*array1, **hash1#{block})")
        check_allocations(1, 0, "required_and_keyword(*array1, *empty_array, **hash1#{block})")

        check_allocations(1, 0, "required_and_keyword(*array1, *empty_array#{block})")
        check_allocations(1, 0, "required_and_keyword(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 1, "required_and_keyword(*array1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "required_and_keyword(*array1, *empty_array, **hash1, **empty_hash#{block})")

        check_allocations(1, 0, "required_and_keyword(*r2k_empty_array1#{block})")
        check_allocations(1, 1, "required_and_keyword(*r2k_array1#{block})")

        # Currently allocates 1 array unnecessarily due to splatarray true
        check_allocations(1, 1, "required_and_keyword(1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "required_and_keyword(1, *empty_array, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "required_and_keyword(*array1, **empty_hash, a: 2#{block})")
        check_allocations(1, 1, "required_and_keyword(*array1, **hash1, **empty_hash#{block})")
        check_allocations(1, 0, "required_and_keyword(*array1, **nil#{block})")
      RUBY
    end

    def test_positional_splat_and_keyword_parameter
      check_allocations(<<~RUBY)
        def self.splat_and_keyword(*b, a: nil#{block}); end

        check_allocations(1, 0, "splat_and_keyword(1, a: 2#{block})")
        check_allocations(1, 0, "splat_and_keyword(1, *empty_array, a: 2#{block})")
        check_allocations(1, 1, "splat_and_keyword(1, a:2, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword(1, **empty_hash, a: 2#{block})")

        check_allocations(1, 0, "splat_and_keyword(1, **nil#{block})")
        check_allocations(1, 0, "splat_and_keyword(1, **empty_hash#{block})")
        check_allocations(1, 0, "splat_and_keyword(1, **hash1#{block})")
        check_allocations(1, 0, "splat_and_keyword(1, *empty_array, **hash1#{block})")
        check_allocations(1, 1, "splat_and_keyword(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword(1, **empty_hash, **hash1#{block})")

        check_allocations(1, 0, "splat_and_keyword(1, *empty_array#{block})")
        check_allocations(1, 1, "splat_and_keyword(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 0, "splat_and_keyword(1, *empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(1, 0, "splat_and_keyword(*array1, a: 2#{block})")

        check_allocations(1, 0, "splat_and_keyword(*array1, **nill#{block})")
        check_allocations(1, 0, "splat_and_keyword(*array1, **empty_hash#{block})")
        check_allocations(1, 0, "splat_and_keyword(*array1, **hash1#{block})")
        check_allocations(1, 0, "splat_and_keyword(*array1, *empty_array, **hash1#{block})")

        check_allocations(1, 0, "splat_and_keyword(*array1, *empty_array#{block})")
        check_allocations(1, 0, "splat_and_keyword(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 1, "splat_and_keyword(*array1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword(*array1, *empty_array, **hash1, **empty_hash#{block})")

        check_allocations(1, 1, "splat_and_keyword(1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword(1, *empty_array, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword(*array1, **empty_hash, a: 2#{block})")
        check_allocations(1, 1, "splat_and_keyword(*array1, **hash1, **empty_hash#{block})")
        check_allocations(1, 0, "splat_and_keyword(*array1, **nil#{block})")

        check_allocations(1, 0, "splat_and_keyword(*r2k_empty_array#{block})")
        check_allocations(1, 1, "splat_and_keyword(*r2k_array#{block})")
        check_allocations(1, 0, "splat_and_keyword(*r2k_empty_array1#{block})")
        check_allocations(1, 1, "splat_and_keyword(*r2k_array1#{block})")
      RUBY
    end

    def test_required_and_keyword_splat_parameter
      check_allocations(<<~RUBY)
        def self.required_and_keyword_splat(b, **kw#{block}); end

        check_allocations(0, 1, "required_and_keyword_splat(1, a: 2#{block})")
        check_allocations(0, 1, "required_and_keyword_splat(1, *empty_array, a: 2#{block})")
        check_allocations(0, 1, "required_and_keyword_splat(1, a:2, **empty_hash#{block})")
        check_allocations(0, 1, "required_and_keyword_splat(1, **empty_hash, a: 2#{block})")

        check_allocations(0, 1, "required_and_keyword_splat(1, **nil#{block})")
        check_allocations(0, 1, "required_and_keyword_splat(1, **empty_hash#{block})")
        check_allocations(0, 1, "required_and_keyword_splat(1, **hash1#{block})")
        check_allocations(0, 1, "required_and_keyword_splat(1, *empty_array, **hash1#{block})")
        check_allocations(0, 1, "required_and_keyword_splat(1, **hash1, **empty_hash#{block})")
        check_allocations(0, 1, "required_and_keyword_splat(1, **empty_hash, **hash1#{block})")

        check_allocations(0, 1, "required_and_keyword_splat(1, *empty_array#{block})")
        check_allocations(0, 1, "required_and_keyword_splat(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "required_and_keyword_splat(1, *empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(0, 1, "required_and_keyword_splat(*array1, a: 2#{block})")

        check_allocations(0, 1, "required_and_keyword_splat(*array1, **nill#{block})")
        check_allocations(0, 1, "required_and_keyword_splat(*array1, **empty_hash#{block})")
        check_allocations(0, 1, "required_and_keyword_splat(*array1, **hash1#{block})")
        check_allocations(1, 1, "required_and_keyword_splat(*array1, *empty_array, **hash1#{block})")

        check_allocations(1, 1, "required_and_keyword_splat(*array1, *empty_array#{block})")
        check_allocations(1, 1, "required_and_keyword_splat(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 1, "required_and_keyword_splat(*array1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "required_and_keyword_splat(*array1, *empty_array, **hash1, **empty_hash#{block})")

        check_allocations(1, 1, "required_and_keyword_splat(*r2k_empty_array1#{block})")
        check_allocations(1, 1, "required_and_keyword_splat(*r2k_array1#{block})")

        # Currently allocates 1 array unnecessarily due to splatarray true
        check_allocations(1, 1, "required_and_keyword_splat(1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "required_and_keyword_splat(1, *empty_array, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "required_and_keyword_splat(*array1, **empty_hash, a: 2#{block})")
        check_allocations(1, 1, "required_and_keyword_splat(*array1, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "required_and_keyword_splat(*array1, **nil#{block})")
      RUBY
    end

    def test_positional_splat_and_keyword_splat_parameter
      check_allocations(<<~RUBY)
        def self.splat_and_keyword_splat(*b, **kw#{block}); end

        check_allocations(1, 1, "splat_and_keyword_splat(1, a: 2#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(1, *empty_array, a: 2#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(1, a:2, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(1, **empty_hash, a: 2#{block})")

        check_allocations(1, 1, "splat_and_keyword_splat(1, **nil#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(1, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(1, **hash1#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(1, *empty_array, **hash1#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(1, **empty_hash, **hash1#{block})")

        check_allocations(1, 1, "splat_and_keyword_splat(1, *empty_array#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(1, *empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(1, 1, "splat_and_keyword_splat(*array1, a: 2#{block})")

        check_allocations(1, 1, "splat_and_keyword_splat(*array1, **nill#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(*array1, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(*array1, **hash1#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(*array1, *empty_array, **hash1#{block})")

        check_allocations(1, 1, "splat_and_keyword_splat(*array1, *empty_array#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 1, "splat_and_keyword_splat(*array1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(*array1, *empty_array, **hash1, **empty_hash#{block})")

        check_allocations(1, 1, "splat_and_keyword_splat(1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(1, *empty_array, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(*array1, **empty_hash, a: 2#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(*array1, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(*array1, **nil#{block})")

        check_allocations(1, 1, "splat_and_keyword_splat(*r2k_empty_array#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(*r2k_array#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(*r2k_empty_array1#{block})")
        check_allocations(1, 1, "splat_and_keyword_splat(*r2k_array1#{block})")
      RUBY
    end

    def test_anonymous_splat_and_anonymous_keyword_splat_parameters
      check_allocations(<<~RUBY)
        def self.anon_splat_and_anon_keyword_splat(*, **#{block}); end

        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, a: 2#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, *empty_array, a: 2#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, a:2, **empty_hash#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, **empty_hash, a: 2#{block})")

        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, **nil#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, **empty_hash#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, **hash1#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, *empty_array, **hash1#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, **empty_hash, **hash1#{block})")

        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, *empty_array#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, *empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(0, 0, "anon_splat_and_anon_keyword_splat(*array1, a: 2#{block})")

        check_allocations(0, 0, "anon_splat_and_anon_keyword_splat(*array1, **nill#{block})")
        check_allocations(0, 0, "anon_splat_and_anon_keyword_splat(*array1, **empty_hash#{block})")
        check_allocations(0, 0, "anon_splat_and_anon_keyword_splat(*array1, **hash1#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(*array1, *empty_array, **hash1#{block})")

        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(*array1, *empty_array#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*array1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*array1, *empty_array, **hash1, **empty_hash#{block})")

        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, *empty_array, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*array1, **empty_hash, a: 2#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*array1, **hash1, **empty_hash#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(*array1, **nil#{block})")

        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*r2k_empty_array#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*r2k_array#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*r2k_empty_array1#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*r2k_array1#{block})")
      RUBY
    end

    def test_nested_anonymous_splat_and_anonymous_keyword_splat_parameters
      check_allocations(<<~RUBY)
        def self.anon_splat_and_anon_keyword_splat(*, **#{block}); t(*, **) end; def self.t(*, **#{block}); end

        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, a: 2#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, *empty_array, a: 2#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, a:2, **empty_hash#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, **empty_hash, a: 2#{block})")

        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, **nil#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, **empty_hash#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, **hash1#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, *empty_array, **hash1#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, **empty_hash, **hash1#{block})")

        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, *empty_array#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(1, *empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(0, 0, "anon_splat_and_anon_keyword_splat(*array1, a: 2#{block})")

        check_allocations(0, 0, "anon_splat_and_anon_keyword_splat(*array1, **nill#{block})")
        check_allocations(0, 0, "anon_splat_and_anon_keyword_splat(*array1, **empty_hash#{block})")
        check_allocations(0, 0, "anon_splat_and_anon_keyword_splat(*array1, **hash1#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(*array1, *empty_array, **hash1#{block})")

        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(*array1, *empty_array#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*array1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*array1, *empty_array, **hash1, **empty_hash#{block})")

        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(1, *empty_array, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*array1, **empty_hash, a: 2#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*array1, **hash1, **empty_hash#{block})")
        check_allocations(1, 0, "anon_splat_and_anon_keyword_splat(*array1, **nil#{block})")

        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*r2k_empty_array#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*r2k_array#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*r2k_empty_array1#{block})")
        check_allocations(1, 1, "anon_splat_and_anon_keyword_splat(*r2k_array1#{block})")
      RUBY
    end

    def test_argument_forwarding
      check_allocations(<<~RUBY)
        def self.argument_forwarding(...); end

        check_allocations(1, 1, "argument_forwarding(1, a: 2#{block})")
        check_allocations(1, 0, "argument_forwarding(1, *empty_array, a: 2#{block})")
        check_allocations(1, 1, "argument_forwarding(1, a:2, **empty_hash#{block})")
        check_allocations(1, 1, "argument_forwarding(1, **empty_hash, a: 2#{block})")

        check_allocations(1, 0, "argument_forwarding(1, **nil#{block})")
        check_allocations(1, 0, "argument_forwarding(1, **empty_hash#{block})")
        check_allocations(1, 0, "argument_forwarding(1, **hash1#{block})")
        check_allocations(1, 0, "argument_forwarding(1, *empty_array, **hash1#{block})")
        check_allocations(1, 1, "argument_forwarding(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "argument_forwarding(1, **empty_hash, **hash1#{block})")

        check_allocations(1, 0, "argument_forwarding(1, *empty_array#{block})")
        check_allocations(1, 1, "argument_forwarding(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 0, "argument_forwarding(1, *empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(0, 0, "argument_forwarding(*array1, a: 2#{block})")

        check_allocations(0, 0, "argument_forwarding(*array1, **nill#{block})")
        check_allocations(0, 0, "argument_forwarding(*array1, **empty_hash#{block})")
        check_allocations(0, 0, "argument_forwarding(*array1, **hash1#{block})")
        check_allocations(1, 0, "argument_forwarding(*array1, *empty_array, **hash1#{block})")

        check_allocations(1, 0, "argument_forwarding(*array1, *empty_array#{block})")
        check_allocations(1, 0, "argument_forwarding(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 1, "argument_forwarding(*array1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "argument_forwarding(*array1, *empty_array, **hash1, **empty_hash#{block})")

        check_allocations(1, 1, "argument_forwarding(1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "argument_forwarding(1, *empty_array, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "argument_forwarding(*array1, **empty_hash, a: 2#{block})")
        check_allocations(1, 1, "argument_forwarding(*array1, **hash1, **empty_hash#{block})")
        check_allocations(1, 0, "argument_forwarding(*array1, **nil#{block})")

        check_allocations(1, 1, "argument_forwarding(*r2k_empty_array#{block})")
        check_allocations(1, 1, "argument_forwarding(*r2k_array#{block})")
        check_allocations(1, 1, "argument_forwarding(*r2k_empty_array1#{block})")
        check_allocations(1, 1, "argument_forwarding(*r2k_array1#{block})")
      RUBY
    end

    def test_nested_argument_forwarding
      check_allocations(<<~RUBY)
        def self.argument_forwarding(...); t(...) end; def self.t(...) end

        check_allocations(1, 1, "argument_forwarding(1, a: 2#{block})")
        check_allocations(1, 0, "argument_forwarding(1, *empty_array, a: 2#{block})")
        check_allocations(1, 1, "argument_forwarding(1, a:2, **empty_hash#{block})")
        check_allocations(1, 1, "argument_forwarding(1, **empty_hash, a: 2#{block})")

        check_allocations(1, 0, "argument_forwarding(1, **nil#{block})")
        check_allocations(1, 0, "argument_forwarding(1, **empty_hash#{block})")
        check_allocations(1, 0, "argument_forwarding(1, **hash1#{block})")
        check_allocations(1, 0, "argument_forwarding(1, *empty_array, **hash1#{block})")
        check_allocations(1, 1, "argument_forwarding(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "argument_forwarding(1, **empty_hash, **hash1#{block})")

        check_allocations(1, 0, "argument_forwarding(1, *empty_array#{block})")
        check_allocations(1, 1, "argument_forwarding(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 0, "argument_forwarding(1, *empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(0, 0, "argument_forwarding(*array1, a: 2#{block})")

        check_allocations(0, 0, "argument_forwarding(*array1, **nill#{block})")
        check_allocations(0, 0, "argument_forwarding(*array1, **empty_hash#{block})")
        check_allocations(0, 0, "argument_forwarding(*array1, **hash1#{block})")
        check_allocations(1, 0, "argument_forwarding(*array1, *empty_array, **hash1#{block})")

        check_allocations(1, 0, "argument_forwarding(*array1, *empty_array#{block})")
        check_allocations(1, 0, "argument_forwarding(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 1, "argument_forwarding(*array1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "argument_forwarding(*array1, *empty_array, **hash1, **empty_hash#{block})")

        check_allocations(1, 1, "argument_forwarding(1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "argument_forwarding(1, *empty_array, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "argument_forwarding(*array1, **empty_hash, a: 2#{block})")
        check_allocations(1, 1, "argument_forwarding(*array1, **hash1, **empty_hash#{block})")
        check_allocations(1, 0, "argument_forwarding(*array1, **nil#{block})")

        check_allocations(1, 1, "argument_forwarding(*r2k_empty_array#{block})")
        check_allocations(1, 1, "argument_forwarding(*r2k_array#{block})")
        check_allocations(1, 1, "argument_forwarding(*r2k_empty_array1#{block})")
        check_allocations(1, 1, "argument_forwarding(*r2k_array1#{block})")
      RUBY
    end

    def test_ruby2_keywords
      check_allocations(<<~RUBY)
        def self.r2k(*a#{block}); end
        singleton_class.send(:ruby2_keywords, :r2k)

        check_allocations(1, 1, "r2k(1, a: 2#{block})")
        check_allocations(1, 1, "r2k(1, *empty_array, a: 2#{block})")
        check_allocations(1, 1, "r2k(1, a:2, **empty_hash#{block})")
        check_allocations(1, 1, "r2k(1, **empty_hash, a: 2#{block})")

        check_allocations(1, 0, "r2k(1, **nil#{block})")
        check_allocations(1, 1, "r2k(1, **empty_hash#{block})")
        check_allocations(1, 1, "r2k(1, **hash1#{block})")
        check_allocations(1, 1, "r2k(1, *empty_array, **hash1#{block})")
        check_allocations(1, 1, "r2k(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "r2k(1, **empty_hash, **hash1#{block})")

        check_allocations(1, 0, "r2k(1, *empty_array#{block})")
        check_allocations(1, 1, "r2k(1, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "r2k(1, *empty_array, *empty_array, **empty_hash#{block})")

        check_allocations(1, 1, "r2k(*array1, a: 2#{block})")

        check_allocations(1, 0, "r2k(*array1, **nill#{block})")
        check_allocations(1, 1, "r2k(*array1, **empty_hash#{block})")
        check_allocations(1, 1, "r2k(*array1, **hash1#{block})")
        check_allocations(1, 1, "r2k(*array1, *empty_array, **hash1#{block})")

        check_allocations(1, 0, "r2k(*array1, *empty_array#{block})")
        check_allocations(1, 1, "r2k(*array1, *empty_array, **empty_hash#{block})")

        check_allocations(1, 1, "r2k(*array1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "r2k(*array1, *empty_array, **hash1, **empty_hash#{block})")

        check_allocations(1, 1, "r2k(1, *empty_array, a: 2, **empty_hash#{block})")
        check_allocations(1, 1, "r2k(1, *empty_array, **hash1, **empty_hash#{block})")
        check_allocations(1, 1, "r2k(*array1, **empty_hash, a: 2#{block})")
        check_allocations(1, 1, "r2k(*array1, **hash1, **empty_hash#{block})")
        check_allocations(1, 0, "r2k(*array1, **nil#{block})")

        check_allocations(1, 0, "r2k(*r2k_empty_array#{block})")
        check_allocations(1, 1, "r2k(*r2k_array#{block})")
        unless defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled?
          # YJIT may or may not allocate depending on arch?
          check_allocations(1, 0, "r2k(*r2k_empty_array1#{block})")
          check_allocations(1, 1, "r2k(*r2k_array1#{block})")
        end
      RUBY
    end

    class WithBlock < self
      def block
        ', &block'
      end
    end
  end
end
