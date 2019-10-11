library(stars)
library(abind)
library(raster)
library(lubridate)
library(jsonlite)
library(dplyr)
library(tibble)
library(tidyr)
library(webutils)
library(arrow)

DEBUG = TRUE
if (DEBUG) {
  options(digits.secs=3)
}

#TODO define float maximum digits

source("data_transformation.R")


.measure_time = function(fun,message,envir=parent.frame()) {
  if (!DEBUG) return(eval(fun,envir = envir))
  tryCatch({
    start = Sys.time()
    eval(fun,envir=envir)
  },error=function(e){
    stop(e$message)
  },finally = {
    cat(message)
    cat("\n")
    print(Sys.time()-start)
  })
}

#* @apiTitle R UDF API
#*
#* Takes a UDFRequest containing data and code and runs the code on the data
#* 
#* @post /udf
udf_json = function(req,res) {
  if (DEBUG) print(format(Sys.time(),format = "%F %H:%M:%OS"))
  
  cat("Started executing at endpoint /udf\n")
  
  json_in = .measure_time(quote(jsonlite::fromJSON(req$postBody)),"Read json. Runtime:")
  
  if (is.null(json_in$code$language) || !tolower(json_in$code$language)=="r") stop("Cannot interprete code source, due to missing programming language.")
  
  # prepare the executable code
  fun = function() {}
  formals(fun) = alist(data=) #TODO also metadata?
  body(fun) = parse(text=json_in$code$source)
  #TODO check which data type comes in, then create an according data structure
  # transform data into stars
  stars_in = .measure_time(quote(json2stars_array(json_in)),"Translated list into stars. Runtime:")
  
  rm(json_in)
  # run the UDF
  stars_out = .measure_time(quote(fun(data=stars_in)),"Executed script. Runtime:")
  #TODO build type related output transformation (user has to define dimensionality)
  # transform stars into JSON
  json_out = .measure_time(quote(stars2json.raster_collection_tiles(stars_obj = stars_out)),"Translated from stars to list. Runtime:")
  
  json=.measure_time(quote(toJSON(json_out,auto_unbox = TRUE)),"Prepared JSON from list. Runtime:")
  
  if (DEBUG) print(format(Sys.time(),format = "%F %H:%M:%OS"))
  res$setHeader(name = "CONTENT-TYPE",value = "application/json")
  res$body = json
  
}

#* Gets the library configuration of this udf service
#* @get /libs
#* @serializer unboxedJSON
get_installed_libraries = function() {
  libs = as.data.frame(installed.packages()[,c("Package","Version")])
  rownames(libs) = NULL

  return(libs)
}

.getBoundary = function(req) {
  unlist(strsplit(req$CONTENT_TYPE,"boundary="))[2]
}

#* @post /udf/parquet
udf_parquet = function(req, res) {
  if (DEBUG) print(format(Sys.time(),format = "%F %H:%M:%OS"))
  
  .measure_time({
    req$rook.input$rewind()
    data = req$rook.input$read()
    form = parse_multipart(body=data,boundary = .getBoundary(req))
    rm(data)
    
    data = read_parquet(BufferReader(form$data$value)) 
  }, message = "Finished reading the parquet input data")
  
  
  .measure_time({
    data = parquet2stars(data)
    
  }, message="Finished translating parquet into stars")
  
  .measure_time({
    
    env = new.env()
    env$data = data
    tryCatch({
      con = rawConnection(form$code$value)
      result = source(file=con,local = env)$value
    }, finally = {
      close(con)
    })
    
    
  }, message = "Finished calculation")
  
  
  
  tryCatch({
    .measure_time({
      res_df = as_tibble(as.data.frame(result))
      
      # adapt middle of pixel assumption
      res_df$x = res_df$x + 0.5
      res_df$y = res_df$y + 0.5
      
      out=arrow::table(res_df)
      tmp_parquet = tempfile(pattern = "result",fileext = ".pq")
      write_parquet(out,tmp_parquet)
      Sys.time()
      
      res$serializer <- "null"
      res$body = readBin(tmp_parquet,what = "raw",n=file.size(tmp_parquet))
      res$setHeader("Content-type", "application/parquet")
      
      res
      
    },"Finished stars -> parquet")
    
    
  }, finally={
    print(Sys.time())
    file.remove(tmp_parquet)
  })
  
}
