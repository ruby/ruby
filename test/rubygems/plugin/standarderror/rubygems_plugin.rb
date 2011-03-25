######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

TestGem::TEST_PLUGIN_STANDARDERROR = :loaded
raise StandardError.new('boom')