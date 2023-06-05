if RbConfig::CONFIG["LIBRUBY_RELATIVE"] == "yes"
  exclude(/test_looks_for_gemdeps_files_automatically_from_binstubs/,
         "can't test before installation")
end
