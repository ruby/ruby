#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Differential fuzzing of the regexp engines (doc/regexp/engine.md). Each
# seed generates patterns and subjects, matches them under
# --regexp-engine=onigmo and under --regexp-engine=rust, and reports the
# lines whose results differ.
#
#   ruby tool/regexp-fuzz.rb --ruby=./ruby --seeds=1..8 --count=5000 [--encodings]
#
# A seed that crashes one engine is reported with the last lines it printed.

require "optparse"
require "open3"
require "rbconfig"

module RegexpFuzz
  ATOMS = %w[a b c ab k K s S . \\w \\W \\d \\s \\h \\b \\B ^ $ \\A \\z \\Z \\G [abc] [^a] [a-c] [[:alpha:]]
             [[:^space:]] \\p{Greek} \\p{^Alpha} \\R \\X \\K é ß ﬀ K \\n \\x41 [\\w&&[^\\d]] [a-z&&[^c]]
             \\u00e9]
  ENC_ATOMS = %w[あ ア 漢 ｱ [あ-ん] [^あ] \\p{Hiragana} \\p{Katakana}]
  GROUPS = ["(%s)", "(?:%s)", "(?<n>%s)", "(?>%s)", "(?=%s)", "(?!%s)", "(?<=%s)", "(?<!%s)", "(?i:%s)",
            "(?m:%s)", "(?~%s)", "(?i)%s", "(%s)|x"]
  QUANTS = ["", "", "", "*", "+", "?", "{2}", "{1,3}", "{0,2}", "*?", "+?", "??", "*+", "++", "{2,}"]
  REFS = ["\\1", "\\k<n>", "(?(1)a|b)", "\\g<n>"]
  ALPHA = ["a", "b", "c", "ab", "k", "K", "s", "S", "é", "ß", "ﬀ", "K", "\n", "\r\n", " ", "1", "_",
           "α", "x", "́"]
  ENC_ALPHA = ["あ", "ア", "漢", "ｱ"]
  ENCODINGS = %w[UTF-8 EUC-JP Shift_JIS Windows-31J ASCII-8BIT ISO-8859-1 UTF-16LE]

  module_function

  def gen(rng, atoms, depth)
    parts = Array.new(rng.rand(1..3)) do
      piece = if depth > 0 && rng.rand < 0.35
        GROUPS.sample(random: rng) % gen(rng, atoms, depth - 1)
      elsif rng.rand < 0.08
        REFS.sample(random: rng)
      else
        atoms.sample(random: rng)
      end
      piece + QUANTS.sample(random: rng)
    end
    rng.rand < 0.15 ? parts.first(2).join("|") : parts.join
  end

  def show(m)
    return "nil" unless m
    (0...m.size).map { |i| m.byteoffset(i).inspect }.join(" ")
  end

  def convert(s, enc)
    enc == Encoding::ASCII_8BIT ? s.b : s.encode(enc)
  end

  # Runs in the child ruby: prints one line per pattern.
  def worker(seed, count, encodings)
    rng = Random.new(seed)
    Regexp.timeout = 2.0
    atoms = encodings ? ATOMS + ENC_ATOMS : ATOMS
    alpha = encodings ? ALPHA + ENC_ALPHA : ALPHA
    count.times do |i|
      enc = encodings ? Encoding.find(ENCODINGS.sample(random: rng)) : Encoding::UTF_8
      src0 = gen(rng, atoms, 3)
      flags = rng.rand(8)
      subjects = Array.new(4) { Array.new(rng.rand(0..12)) { alpha.sample(random: rng) }.join }
      begin
        re = Regexp.new(convert(src0, enc), flags)
      rescue EncodingError
        puts "#{i} #{enc} skip"
        next
      rescue RegexpError, ArgumentError => e
        puts "#{i} #{enc} #{src0.inspect} compile: #{e.class}: #{e.message.b.inspect}"
        next
      end
      out = subjects.map do |s0|
        str = begin
          convert(s0, enc)
        rescue EncodingError
          next "skip"
        end
        [show(re.match(str)), str.scan(re).size, str.index(re).inspect, str.rindex(re).inspect].join(" ")
      rescue Regexp::TimeoutError
        "timeout"
      rescue => e
        "#{e.class}: #{e.message.b.inspect}"
      end
      puts "#{i} #{enc} #{src0.inspect} #{flags} #{re.names.inspect} #{Regexp.linear_time?(re)} #{out.join(' | ')}"
    end
  end

  def run_engine(ruby, engine, seed, count, encodings)
    args = [*ruby, "--regexp-engine=#{engine}", __FILE__, "--worker", seed.to_s, count.to_s]
    args << "--encodings" if encodings
    out, status = Open3.capture2e(*args)
    # Warnings carry the line number of this file, which may differ by run.
    [out.b.gsub(/#{Regexp.escape(File.basename(__FILE__))}:\d+:/n, "N:").lines, status]
  end

  def driver(ruby, seeds, count, encodings)
    failed = false
    seeds.each do |seed|
      a, sa = run_engine(ruby, "onigmo", seed, count, encodings)
      b, sb = run_engine(ruby, "rust", seed, count, encodings)
      unless sa.success? && sb.success?
        failed = true
        puts "seed #{seed}: onigmo #{sa.inspect}, rust #{sb.inspect}"
        puts((sa.success? ? b : a).last(5))
        next
      end
      diffs = a.zip(b).reject { |x, y| x == y }
      failed ||= !diffs.empty? || a.size != b.size
      puts "seed #{seed}: #{a.size} lines, #{diffs.size} differ"
      diffs.first(5).each { |x, y| puts "  onigmo: #{x}  rust:   #{y}" }
    end
    exit(failed ? 1 : 0)
  end
end

if ARGV.first == "--worker"
  RegexpFuzz.worker(Integer(ARGV[1]), Integer(ARGV[2]), ARGV.include?("--encodings"))
  exit
end

ruby = [RbConfig.ruby]
seeds = 1..4
count = 2000
encodings = false
OptionParser.new do |o|
  o.on("--ruby=CMD", "ruby to test (may include options)") { |v| ruby = v.split }
  o.on("--seeds=RANGE", "for example 1..8") { |v| a, b = v.split("..").map { Integer(_1) }; seeds = a..(b || a) }
  o.on("--count=N", Integer) { |v| count = v }
  o.on("--encodings", "patterns and subjects in seven encodings") { encodings = true }
end.parse!
RegexpFuzz.driver(ruby, seeds, count, encodings)
