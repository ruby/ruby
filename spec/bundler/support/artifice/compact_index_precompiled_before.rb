# frozen_string_literal: true

require_relative "compact_index"

Artifice.deactivate

class CompactIndexPrecompiledBefore < CompactIndexAPI
  get "/info/:name" do
    etag_response do
      gem = gems.find {|g| g.name == params[:name] }
      move_ruby_variant_to_the_end(CompactIndex.info(gem ? gem.versions : []))
    end
  end

  private

  def move_ruby_variant_to_the_end(response)
    lines = response.split("\n")
    ruby = lines.find {|line| /\A\d+\.\d+\.\d* \|/.match(line) }
    lines.delete(ruby)
    lines.push(ruby).join("\n")
  end
end

Artifice.activate_with(CompactIndexPrecompiledBefore)
