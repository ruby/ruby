# frozen_string_literal: true

require_relative "test_helper"

module Ruby::Prism
  class HeredocRecoveryTest < TestCase
    def test_missing_token_after_unterminated_heredoc
      result = assert_bounded_locations("//?<<0 a ")
      colon = result.errors.find { |error| error.type == :ternary_colon }
      assert_equal 6, colon.location.start_offset
      assert_equal 0, colon.location.length
      assert_equal " a", result.value.statements.body.first.subsequent.location.slice
    end

    def test_missing_token_after_terminated_heredoc
      result = assert_bounded_locations("//?<<A a\nbody\nA\n")
      assert_equal [:ternary_colon], result.errors.map(&:type)
      assert_equal 6, result.errors.first.location.start_offset
      assert_equal " a", result.value.statements.body.first.subsequent.location.slice
    end

    def test_discarded_hash_pattern_heredoc_at_eof
      result = assert_bounded_locations("x in {<<0\n\#{class")
      assert_equal :pattern_hash_key, result.errors.first.type
    end

    def test_discarded_hash_pattern_heredoc_resumes_on_declaration_line
      ["body\n", "\#{<<B}\ninner\nB\n"].each do |body|
        result = assert_bounded_locations("x in {<<A}; after\n#{body}A\n")
        assert_equal [:pattern_hash_key, :pattern_hash_key_label], result.errors.map(&:type)
        assert_equal :after, result.value.statements.body.last.name
        assert_equal "after", result.value.statements.body.last.location.slice
      end
    end

    def test_discarded_heredoc_in_interpolation_recovery
      ['"', '`', '/', '%Q[', '%W[', '%I['].each do |opening|
        source = '->x:' + opening + '#{)<<"' + "\n" + '#{f' + "\n" + '"#{a}"C{'
        result = assert_bounded_locations(source)
        assert_predicate result, :failure?
      end
    end

    def test_heredoc_end_unwinds_unclosed_interpolation
      ["<<0\n\#{f{", "<<0\n\#{{{{s[f{"].each do |source|
        assert_bounded_locations(source)
      end
    end

    def test_documentation_at_eof_inside_interpolation
      ["", "a", "if", "foo"].each do |tail|
        source = "if A\n<<0\n\#{\n=begin\n#{tail}"
        result = assert_bounded_locations(source)
        assert_equal "=begin\n#{tail}", result.comments.first.location.slice
        assert_equal source.bytesize, result.comments.first.location.end_offset
      end

      source = "if A\n<<0\n\#{\n__END__\ndata\n"
      result = assert_bounded_locations(source)
      assert_equal "__END__\ndata\n", result.data_loc.slice
    end

    private

    def assert_bounded_locations(source)
      result = Ruby::Prism.parse(source)
      nodes = [result.value]

      until nodes.empty?
        node = nodes.pop
        locations = [node.location] + node.deconstruct_keys(nil).values.grep(Location)
        locations.each { |location| assert_operator location.end_offset, :<=, source.bytesize, source.inspect }
        nodes.concat(node.compact_child_nodes)
      end

      result.errors.each { |error| assert_operator error.location.end_offset, :<=, source.bytesize, source.inspect }
      result
    end
  end
end
