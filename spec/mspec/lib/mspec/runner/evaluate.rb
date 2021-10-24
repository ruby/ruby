class SpecEvaluate
  include MSpecMatchers

  def self.desc=(desc)
    @desc = desc
  end

  def self.desc
    @desc ||= "evaluates "
  end

  def initialize(ruby, desc)
    @ruby = ruby.rstrip
    @desc = desc || self.class.desc
  end

  # Formats the Ruby source code for reabable output in the -fs formatter
  # option. If the source contains no newline characters, wraps the source in
  # single quotes to set if off from the rest of the description string. If
  # the source does contain newline characters, sets the indent level to four
  # characters.
  def format(ruby, newline = true)
    if ruby.include?("\n")
      lines = ruby.each_line.to_a
      if /( *)/ =~ lines.first
        if $1.size > 4
          dedent = $1.size - 4
          ruby = lines.map { |l| l[dedent..-1] }.join
        else
          indent = " " * (4 - $1.size)
          ruby = lines.map { |l| "#{indent}#{l}" }.join
        end
      end
      "\n#{ruby}"
    else
      "'#{ruby.lstrip}'"
    end
  end

  def define(&block)
    ruby = @ruby
    desc = @desc
    evaluator = self

    specify "#{desc} #{format ruby}" do
      evaluator.instance_eval(ruby)
      evaluator.instance_eval(&block)
    end
  end
end

def evaluate(str, desc = nil, &block)
  SpecEvaluate.new(str, desc).define(&block)
end
