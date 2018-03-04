require_relative '../../spec_helper'
require_relative '../kernel/shared/sprintf'

describe "File#printf" do
  it_behaves_like :kernel_sprintf, -> (format, *args) {
    begin
      @filename = tmp("printf.txt")

      File.open(@filename, "w", encoding: "utf-8") do |f|
        f.printf(format, *args)
      end

      File.read(@filename, encoding: "utf-8")
    ensure
      rm_r @filename
    end
  }
end
