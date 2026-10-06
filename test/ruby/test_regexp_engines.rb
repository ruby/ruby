# frozen_string_literal: false
require 'test/unit'

# Compares the Rust regexp engine with Onigmo on patterns taken from the
# regexp tests themselves.
class TestRegexpEngines < Test::Unit::TestCase
  SOURCES = %w[
    test_regexp.rb test_m17n.rb test_m17n_comb.rb test_string.rb test_unicode_escape.rb
  ].map { |f| File.join(__dir__, f) } + Dir.glob(File.join(__dir__, "enc", "*.rb"))

  ENCODINGS = %w[UTF-8 US-ASCII ASCII-8BIT EUC-JP Windows-31J UTF-16LE].map { |e| Encoding.find(e) }

  # Optimizations that read the 256-byte map (Boyer-Moore skip or char map).
  MAP_OPTIMIZATIONS = [2, 3, 5, 6, 7]

  # Ruby rejects escapes that do not form a character of the encoding
  # before either engine sees the pattern.
  ESCAPE_ERRORS = /\A(?:too short escaped multibyte character|invalid multibyte escape)\b/

  def setup
    require '-test-/regexp'
    omit "the Rust regexp engine is not built" unless Bug::Regexp.rust_available?
  end

  def self.patterns
    @patterns ||= begin
      require 'ruby/prism'
      found = {}
      SOURCES.each do |file|
        Ruby::Prism.parse_file(file).value.breadth_first_search do |node|
          if node.is_a?(Ruby::Prism::RegularExpressionNode)
            opts = (node.ignore_case? ? 1 : 0) | (node.extended? ? 2 : 0) | (node.multi_line? ? 4 : 0)
            found[[node.content, opts]] = true
          end
          false
        end
      end
      found.keys
    end
  end

  def compile_both(src, opts)
    onigmo = Bug::Regexp.compile_info(:onigmo, src, opts)
    rust = Bug::Regexp.compile_info(:rust, src, opts)
    if onigmo.is_a?(Hash) && rust.is_a?(Hash)
      ignored = MAP_OPTIMIZATIONS.include?(onigmo[:optimize]) ? [] : [:map]
      # Onigmo sets the distances only along with an optimization.
      ignored += [:dmin, :dmax] if onigmo[:optimize] == 0
      ignored.each { |k| onigmo.delete(k); rust.delete(k) }
    end
    [onigmo, rust]
  end

  def rejected_by_ruby?(src, opts)
    Regexp.new(src, opts)
    false
  rescue RegexpError => e
    ESCAPE_ERRORS.match?(e.message.b)
  end

  def test_compiled_form
    verbose, $VERBOSE = $VERBOSE, nil
    diffs = []
    self.class.patterns.each do |content, opts|
      ENCODINGS.each do |enc|
        src = enc.ascii_compatible? ? content.b.force_encoding(enc) : (content.encode(enc) rescue next)
        next if rejected_by_ruby?(src, opts)
        onigmo, rust = compile_both(src, opts)
        diffs << [content, opts, enc, onigmo, rust] unless onigmo == rust
      end
    end
    assert_empty(diffs.first(5).map { |c, o, e, x, y|
      keys = (x.is_a?(Hash) && y.is_a?(Hash)) ? (x.keys | y.keys).reject { |k| x[k] == y[k] } : nil
      "#{c.inspect} opts=#{o} #{e}: #{keys ? keys.inspect : "#{x.inspect} vs #{y.inspect}"}"
    })
  ensure
    $VERBOSE = verbose
  end

  def test_compile_errors
    [
      "(", ")", "[", "a{2,1}", "(?<n>a)\\k<m>", "(?<=a*)", "\\g<x>", "(?<a>\\g<a>)",
      "[b-a]", "(?<n>a)(b)\\1", "\\p{Foo}", "a{100001}", "(?",
    ].each do |pat|
      onigmo, rust = compile_both(pat.dup.force_encoding("UTF-8"), 0)
      assert_equal(onigmo, rust, pat)
    end
  end

  def test_default_engine_without_option
    # Not through EnvUtil, which passes --regexp-engine of this process.
    out = IO.popen([EnvUtil.rubybin, "--disable=gems", "-e", 'print "éx".grapheme_clusters.size'],
                   err: [:child, :out], &:read)
    assert_equal("2", out)
  end

  def test_warnings
    ["[aa]", "[a-z&&a-z]", "a**", "\\y", "[\\w-a]"].each do |pat|
      src = pat.dup.force_encoding("UTF-8")
      warning_of = ->(engine) { EnvUtil.verbose_warning { Bug::Regexp.compile_info(engine, src) } }
      assert_equal(warning_of[:onigmo], warning_of[:rust], pat)
    end
  end
end
