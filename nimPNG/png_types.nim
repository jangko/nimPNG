type
  PNGFilterStrategy* = enum
    #every filter at zero
    LFS_ZERO,
    #Use filter that gives minimum sum, as described in the official PNG filter heuristic.
    LFS_MINSUM,
    #Use the filter type that gives smallest Shannon entropy for this scanLine. Depending
    #on the image, this is better or worse than minsum.
    LFS_ENTROPY,
    #Brute-force-search PNG filters by compressing each filter for each scanLine.
    #Experimental, very slow, and only rarely gives better compression than MINSUM.
    LFS_BRUTE_FORCE,
    #use predefined_filters buffer: you specify the filter type for each scanLine
    LFS_PREDEFINED