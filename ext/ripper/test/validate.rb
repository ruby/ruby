require 'ripper.so'

class R < Ripper
  def initialize(*args)
    super
    @lineno = 0
  end

  def parse
    result = super
    puts "#{@lineno}:result: #{rawVALUE(result)}"
    validate_object result
    p result
    result
  end

  def on__nl(str)
    @lineno += 1
  end

  def on__ignored_nl(str)
    @lineno += 1
  end

  def on__comment(cmt)
    @lineno += 1
  end

  def on__embdoc_beg(str)
    @lineno += 1
  end

  def on__embdoc(str)
    @lineno += 1
  end

  def on__embdoc_end(str)
    @lineno += 1
  end

  def method_missing(mid, *args)
    puts mid
    args.each_with_index do |a,idx|
      puts "#{@lineno}:#{mid}\##{idx+1}: #{rawVALUE(a)}"
      validate_object a
      p a
    end
    args[0]
  end

  def warn(*args)
  end

  def warning(*args)
  end

  unless respond_to?(:validate_object)
    def validate_object(x)
      x
    end
    def rawVALUE(x)
      x.object_id
    end
  end
end

fname = (ARGV[0] || 'test/src_rb')
R.new(File.read(fname), fname, 1).parse
