# frozen_string_literal: true

TestGem::TEST_PLUGIN_STANDARDERROR = :loaded
raise StandardError.new("boom")
