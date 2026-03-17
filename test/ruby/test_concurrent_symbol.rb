# frozen_string_literal: false
require 'test/unit'

# Tests for concurrent symbol table operations.
#
# The symbol table is backed by a lock-free concurrent_set using Robin Hood
# probing with atomic CAS. These tests exercise that data structure indirectly
# through String#to_sym and related symbol APIs.
class TestConcurrentSymbol < Test::Unit::TestCase
  def test_concurrent_symbol_creation_from_threads
    # Multiple threads creating unique symbols — exercises find_or_insert
    n_threads = 4
    n_per_thread = 200
    prefix = "thr_sym_#{object_id}_"

    threads = n_threads.times.map do |t|
      Thread.new do
        n_per_thread.times.map do |i|
          "#{prefix}#{t}_#{i}".to_sym
        end
      end
    end

    results = threads.map(&:value)

    # Each thread should have produced unique symbols
    all_syms = results.flatten
    assert_equal n_threads * n_per_thread, all_syms.uniq.size
  end

  def test_concurrent_deduplication_from_threads
    # Multiple threads creating the SAME symbols — exercises CAS dedup
    n_threads = 4
    prefix = "dedup_sym_#{object_id}_"
    names = 100.times.map { |i| "#{prefix}#{i}" }

    threads = n_threads.times.map do
      Thread.new do
        names.map(&:to_sym)
      end
    end

    results = threads.map(&:value)

    # All threads should get identical symbol object_ids for each name
    n_threads.times do |t1|
      n_threads.times do |t2|
        next if t1 == t2
        results[t1].each_with_index do |sym, i|
          assert_same sym, results[t2][i],
            "symbol for #{names[i]} should be identical across threads"
        end
      end
    end
  end

  def test_symbol_lookup_during_concurrent_creation
    # Pre-create symbols, then look them up while other threads create new ones
    prefix = "lookup_sym_#{object_id}_"
    existing = 50.times.map { |i| "#{prefix}existing_#{i}".to_sym }

    found = Queue.new
    creator = Thread.new do
      50.times { |i| "#{prefix}new_#{i}".to_sym }
    end
    finder = Thread.new do
      existing.each do |sym|
        name = sym.to_s
        found << [sym, name.to_sym]
      end
    end

    creator.join
    finder.join

    found.size.times do
      original, looked_up = found.pop
      assert_same original, looked_up
    end
  end

  def test_many_symbols_trigger_resize
    # The concurrent_set starts with capacity 1024 and resizes at 75% load.
    # Creating enough unique symbols forces at least one resize.
    prefix = "resize_sym_#{object_id}_"
    symbols = 2000.times.map { |i| "#{prefix}#{i}".to_sym }

    # All symbols should be findable after resize
    2000.times do |i|
      assert_same symbols[i], "#{prefix}#{i}".to_sym,
        "symbol #{i} should survive resize"
    end
  end

  def test_concurrent_symbol_creation_from_ractors
    assert_ractor(<<~'RUBY')
      n_ractors = 4
      n_per_ractor = 200

      ractors = n_ractors.times.map do |r|
        Ractor.new(r, n_per_ractor) do |r_id, count|
          count.times.map do |i|
            "ractor_sym_#{r_id}_#{i}".to_sym
          end
        end
      end

      results = ractors.map(&:value)

      all_syms = results.flatten
      assert_equal n_ractors * n_per_ractor, all_syms.uniq.size
    RUBY
  end

  def test_concurrent_deduplication_from_ractors
    assert_ractor(<<~'RUBY')
      n_ractors = 4
      names = 100.times.map { |i| "ractor_dedup_#{i}" }
      frozen_names = Ractor.make_shareable(names.map(&:freeze).freeze)

      ractors = n_ractors.times.map do
        Ractor.new(frozen_names) do |ns|
          ns.map(&:to_sym)
        end
      end

      results = ractors.map(&:value)

      # All ractors should resolve identical symbol objects
      n_ractors.times do |r1|
        n_ractors.times do |r2|
          next if r1 == r2
          results[r1].each_with_index do |sym, i|
            assert_equal sym, results[r2][i],
              "symbol for #{frozen_names[i]} should be identical across ractors"
          end
        end
      end
    RUBY
  end

  def test_concurrent_symbol_resize_from_ractors
    assert_ractor(<<~'RUBY')
      # Each ractor creates many unique symbols to stress the resize path
      n_ractors = 4
      n_per_ractor = 500

      ractors = n_ractors.times.map do |r|
        Ractor.new(r, n_per_ractor) do |r_id, count|
          syms = count.times.map do |i|
            "ractor_resize_#{r_id}_#{i}".to_sym
          end
          # Verify all our symbols are findable
          count.times do |i|
            found = "ractor_resize_#{r_id}_#{i}".to_sym
            raise "symbol mismatch at #{i}" unless found == syms[i]
          end
          :ok
        end
      end

      results = ractors.map(&:value)
      assert_equal [:ok] * n_ractors, results
    RUBY
  end
end
