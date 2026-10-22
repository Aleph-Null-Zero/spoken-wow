setfenv(1, VoiceOver)
Version = {}

local CLIENT_VERSION, BUILD, _, INTERFACE_VERSION = GetBuildInfo()

Version.Client                  = CLIENT_VERSION
Version.Build                   = BUILD
Version.Interface               = INTERFACE_VERSION or 0
Version.IsRetailVanilla         = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC or nil
Version.IsRetailBurningCrusade  = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC or nil
Version.IsRetailWrath           = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC or nil
Version.IsRetailMainline        = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE or nil
