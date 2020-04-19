require_relative "test_helper"
require "benchmark"

class BenchmarkTest < StdlibTest
  target Benchmark
  library "benchmark"

  using hook.refinement

  def test_benchmark
    n = 10

    Benchmark.benchmark(Benchmark::CAPTION, 7, Benchmark::FORMAT, ">total:", ">avg:") do |x|
      tf = x.report("for:")   { for i in 1..n; a = "1"; end }
      tt = x.report("times:") { n.times do   ; a = "1"; end }
      tu = x.report("upto:")  { 1.upto(n) do ; a = "1"; end }
      [tf+tt+tu, (tf+tt+tu)/3]
    end
  end

  def test_bmbm
    array = (1..30).map { rand }

    Benchmark.bmbm do |x|
      x.report("sort!") { array.dup.sort! }
      x.report("sort")  { array.dup.sort  }
    end
  end

  def test_bm
    n = 5

    Benchmark.bm(7) do |x|
      x.report("for:")   { for i in 1..n; a = "1"; end }
      x.report("times:") { n.times do   ; a = "1"; end }
      x.report("upto:")  { 1.upto(n) do ; a = "1"; end }
    end
  end
end

class BenchmarkReportTest < StdlibTest
  target Benchmark::Report
  library "benchmark"

  using hook.refinement

  def test_benchmark
    n = 10

    Benchmark.benchmark(Benchmark::CAPTION, 7, Benchmark::FORMAT, ">total:", ">avg:") do |x|
      tf = x.report("for:")   { for i in 1..n; a = "1"; end }
      tt = x.report("times:") { n.times do   ; a = "1"; end }
      tu = x.report("upto:")  { 1.upto(n) do ; a = "1"; end }
      [tf+tt+tu, (tf+tt+tu)/3]
    end
  end

  def test_bmbm
    array = (1..30).map { rand }

    Benchmark.bmbm do |x|
      x.report("sort!") { array.dup.sort! }
      x.report("sort")  { array.dup.sort  }
    end
  end

  def test_bm
    n = 5

    Benchmark.bm(7) do |x|
      x.report("for:")   { for i in 1..n; a = "1"; end }
      x.report("times:") { n.times do   ; a = "1"; end }
      x.report("upto:")  { 1.upto(n) do ; a = "1"; end }
    end
  end
end
