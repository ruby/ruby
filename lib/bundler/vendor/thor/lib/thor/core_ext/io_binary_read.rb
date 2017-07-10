class IO #:nodoc:
  class << self
    def binread(file, *args)
      fail ArgumentError, "wrong number of arguments (#{1 + args.size} for 1..3)" unless args.size < 3
      File.open(file, "rb") do |f|
        f.read(*args)
      end
    end unless method_defined? :binread
  end
end
