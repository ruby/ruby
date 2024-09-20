module YAMLSpecs
  COMPLEX_KEY_1 = <<~EOY
      ? # PLAY SCHEDULE
        - Detroit Tigers
        - Chicago Cubs
      :
        - 2001-07-23

      ? [ New York Yankees,
          Atlanta Braves ]
      : [ 2001-07-02, 2001-08-12,
         2001-08-14 ]
  EOY

  MULTIDOCUMENT = <<~EOY
  ---
  - Mark McGwire
  - Sammy Sosa
  - Ken Griffey

  # Team ranking
  ---
  - Chicago Cubs
  - St Louis Cardinals
  EOY
end
