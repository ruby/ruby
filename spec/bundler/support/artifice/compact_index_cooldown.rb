# frozen_string_literal: true

require_relative "helpers/compact_index_cooldown"
require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexCooldownAPI)
