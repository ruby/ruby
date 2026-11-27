# frozen_string_literal: true
module ProcCallFrozenSpecs
  def self.call
    proc {|a| a }.call("sometext")
  end

  def self.call_freeze
    proc {|a| a }.call("sometext".freeze)
  end
end
