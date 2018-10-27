# frozen_string_literal: true
module ProcArefFrozenSpecs
  def self.aref
    proc {|a| a }["sometext"]
  end

  def self.aref_freeze
    proc {|a| a }["sometext".freeze]
  end
end
