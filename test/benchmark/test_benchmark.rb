# frozen_string_literal: false
require 'test/unit'
require 'benchmark'

class TestBenchmark < Test::Unit::TestCase
  BENCH_FOR_TIMES_UPTO = lambda do |x|
    n = 1000
    tf = x.report("for:")   { for _ in 1..n; '1'; end }
    tt = x.report("times:") { n.times do   ; '1'; end }
    tu = x.report("upto:")  { 1.upto(n) do ; '1'; end }
    [tf+tt+tu, (tf+tt+tu)/3]
  end

  BENCH_FOR_TIMES_UPTO_NO_LABEL = lambda do |x|
    n = 1000
    x.report { for _ in 1..n; '1'; end }
    x.report { n.times do   ; '1'; end }
    x.report { 1.upto(n) do ; '1'; end }
  end

  def labels
    %w[first second third]
  end

  def bench(type = :bm, *args, &block)
    if block
      Benchmark.send(type, *args, &block)
    else
      Benchmark.send(type, *args) do |x|
        labels.each { |label|
          x.report(label) {}
        }
      end
    end
  end

  def capture_output
    capture_io { yield }.first.gsub(/[ \-]\d\.\d{6}/, ' --time--')
  end

  def capture_bench_output(type, *args, &block)
    capture_output { bench(type, *args, &block) }
  end

  def test_tms_outputs_nicely
    assert_equal("  0.000000   0.000000   0.000000 (  0.000000)\n", Benchmark::Tms.new.to_s)
    assert_equal("  1.000000   2.000000  10.000000 (  5.000000)\n", Benchmark::Tms.new(1,2,3,4,5).to_s)
    assert_equal("1.000000 2.000000 3.000000 4.000000 10.000000 (5.000000) label",
                 Benchmark::Tms.new(1,2,3,4,5,'label').format('%u %y %U %Y %t %r %n'))
    assert_equal("1.000000 2.000", Benchmark::Tms.new(1).format('%u %.3f', 2))
    assert_equal("100.000000 150.000000 250.000000 (200.000000)\n",
                 Benchmark::Tms.new(100, 150, 0, 0, 200).to_s)
  end

  def test_tms_wont_modify_the_format_String_given
    format = "format %u"
    Benchmark::Tms.new.format(format)
    assert_equal("format %u", format)
  end

  BENCHMARK_OUTPUT_WITH_TOTAL_AVG = <<BENCH
              user     system      total        real
for:      --time--   --time--   --time-- (  --time--)
times:    --time--   --time--   --time-- (  --time--)
upto:     --time--   --time--   --time-- (  --time--)
>total:   --time--   --time--   --time-- (  --time--)
>avg:     --time--   --time--   --time-- (  --time--)
BENCH

  def test_benchmark_does_not_print_any_space_if_the_given_caption_is_empty
    assert_equal(<<-BENCH, capture_bench_output(:benchmark))
first  --time--   --time--   --time-- (  --time--)
second  --time--   --time--   --time-- (  --time--)
third  --time--   --time--   --time-- (  --time--)
BENCH
  end

  def test_benchmark_makes_extra_calcultations_with_an_Array_at_the_end_of_the_benchmark_and_show_the_result
    assert_equal(BENCHMARK_OUTPUT_WITH_TOTAL_AVG,
      capture_bench_output(:benchmark,
        Benchmark::CAPTION, 7,
        Benchmark::FORMAT, ">total:", ">avg:",
        &BENCH_FOR_TIMES_UPTO))
  end

  def test_bm_returns_an_Array_of_the_times_with_the_labels
    [:bm, :bmbm].each do |meth|
      capture_io do
        results = bench(meth)
        assert_instance_of(Array, results)
        assert_equal(labels.size, results.size)
        results.zip(labels).each { |tms, label|
          assert_instance_of(Benchmark::Tms, tms)
          assert_equal(label, tms.label)
        }
      end
    end
  end

  def test_bm_correctly_output_when_the_label_width_is_given
    assert_equal(<<-BENCH, capture_bench_output(:bm, 6))
             user     system      total        real
first    --time--   --time--   --time-- (  --time--)
second   --time--   --time--   --time-- (  --time--)
third    --time--   --time--   --time-- (  --time--)
BENCH
  end

  def test_bm_correctly_output_when_no_label_is_given
    assert_equal(<<-BENCH, capture_bench_output(:bm, &BENCH_FOR_TIMES_UPTO_NO_LABEL))
       user     system      total        real
   --time--   --time--   --time-- (  --time--)
   --time--   --time--   --time-- (  --time--)
   --time--   --time--   --time-- (  --time--)
BENCH
  end

  def test_bm_can_make_extra_calcultations_with_an_array_at_the_end_of_the_benchmark
    assert_equal(BENCHMARK_OUTPUT_WITH_TOTAL_AVG,
      capture_bench_output(:bm, 7, ">total:", ">avg:",
        &BENCH_FOR_TIMES_UPTO))
  end

  BMBM_OUTPUT = <<BENCH
Rehearsal ------------------------------------------
first    --time--   --time--   --time-- (  --time--)
second   --time--   --time--   --time-- (  --time--)
third    --time--   --time--   --time-- (  --time--)
--------------------------------- total: --time--sec

             user     system      total        real
first    --time--   --time--   --time-- (  --time--)
second   --time--   --time--   --time-- (  --time--)
third    --time--   --time--   --time-- (  --time--)
BENCH

  def test_bmbm_correctly_guess_the_label_width_even_when_not_given
    assert_equal(BMBM_OUTPUT, capture_bench_output(:bmbm))
  end

  def test_bmbm_correctly_output_when_the_label_width_is_given__bmbm_ignore_it__but_it_is_a_frequent_mistake
    assert_equal(BMBM_OUTPUT, capture_bench_output(:bmbm, 6))
  end

  def test_report_item_shows_the_title__even_if_not_a_string
    assert_operator(capture_bench_output(:bm) { |x| x.report(:title) {} }, :include?, 'title')
    assert_operator(capture_bench_output(:bmbm) { |x| x.report(:title) {} }, :include?, 'title')
  end

  def test_bugs_ruby_dev_40906_can_add_in_place_the_time_of_execution_of_the_block_given
    t = Benchmark::Tms.new
    assert_equal(0, t.real)
    t.add! { sleep 0.1 }
    assert_not_equal(0, t.real)
  end

  def test_realtime_output
    sleeptime = 1.0
    realtime = Benchmark.realtime { sleep sleeptime }
    assert_operator sleeptime, :<, realtime
  end
end
