
json2stars_array = function(json) {
  # raster_collection_tile order: [band][time][y][x]
  
  arr = abind(band=json$data$raster_collection_tiles$data,along=0)
  
  # TODO this only applies for one case, but what if the time dimension is dropped and/or band?
  # rearrange dim order
  arr_new = aperm(arr,c(4,3,2,1))
  
  dims = dim(arr_new)
  names(dims) = c("x","y","time","band")
  dim(arr_new) = dims
  
  s = st_as_stars(arr_new)
  start_times = as_datetime(json$data$raster_collection_tiles$start_times[[1]])
  ymin = json$data$raster_collection_tiles[1,]$extent$south
  xmin = json$data$raster_collection_tiles[1,]$extent$west
  dx = json$data$raster_collection_tiles[1,]$extent$width
  dy = json$data$raster_collection_tiles[1,]$extent$height
  s = st_set_dimensions(s,which="x",refsys=json$data$proj, offset=xmin, delta=dx)
  s = st_set_dimensions(s,which="y",refsys=json$data$proj,offset=ymin, delta=dy)
  #TODO think about having a non continuous time series, e.g. just some intervals
  s = st_set_dimensions(s,which="time",offset=start_times[1],delta=mean(diff(start_times)))
  
  names(s)=c("value")
  
  return(s)
}

stars2json.raster_collection_tiles = function(stars_obj) {
  # predefined dimension names [band][time][y][x]
  order = c("band","time","y","x")
  stars_obj = aperm(stars_obj, order[order %in% names(dim(stars_obj))])
  
  if ("band" %in% names(dim(stars_obj))) {
    band_names = st_get_dimension_values(stars_obj,"band")
    bands = lapply(seq_along(band_names),function(dimval) {
      list(
        id = as.character(band_names[dimval]),
        data = stars::slice.stars(stars_obj,along="band",index=dimval)[[1]]
      )
    })
  } else {
    # use attributes as bands:
    band_names = names(stars_obj)
    bands = lapply(seq_along(band_names),function(dimval) {
      list(
        id = as.character(band_names[dimval]),
        data = stars_obj[[dimval]]
      )
    })
  }
  
  bands = lapply(bands,function(band) {
    # add time values if available
    if ("time" %in% names(dim(stars_obj))) {
      values = st_get_dimension_values(stars_obj, which="time")
      
      band$start_times = NA
      band$end_times = NA
      
      if ("Intervals" %in% class(values)) {
        band$start_times = int_start(values)
        band$end_times = int_end((values))
      }
      
      if ("POSIXt" %in% class(values)) {
        band$start_times = values
        band$end_times = band$start_times+st_dimensions(stars_obj)$time$delta
      }
    }
    
    # add extent
    if (all(c("x","y") %in% names(dim(stars_obj)))) {
      bbox = st_bbox(stars_obj)
      
      band$extent = list(
        top = bbox$ymax,
        bottom = bbox$ymin,
        left = bbox$xmin,
        right=bbox$xmax,
        width = st_dimensions(stars_obj)$x$delta,
        height = st_dimensions(stars_obj)$y$delta
      )
    }
    return(band)
  })
  
  srs = st_crs(stars_obj)$proj4string
  
  return(list(
    proj=srs,
    raster_collection_tiles=bands
  ))
}

parquet2stars = function(parquet) {
  
  # arrange is time consuming
  parquet %<>% dplyr::select(x,y,time,band,value) %>% dplyr::arrange(time,band,y,x)
  
  
  cube = base::array(parquet$value)
  dim(cube) = c(unique(parquet$x) %>% length,
                unique(parquet$y) %>% length,
                unique(parquet$time) %>% length,
                unique(parquet$band) %>% length)
  names(dim(cube)) = c("x","y","time", "band")
  
  return(st_as_stars(cube))
}