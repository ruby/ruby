# frozen_string_literal: true
class LessThanProc < Proc
  attr_accessor :present

  def self.with(present)
    provided = Gem::Version.new(present.dup)
    new do |required|
      if required =~ /[=><~]/
        !Gem::Requirement.new(required).satisfied_by?(provided)
      else
        provided < Gem::Version.new(required)
      end
    end.tap {|l| l.present = present }
  end

  def inspect
    "\"=< #{present}\""
  end
end
