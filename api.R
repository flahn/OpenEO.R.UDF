library(stars)
library(abind)
library(raster)
library(lubridate)

DEBUG = TRUE

source("data_transformation.R")

# ============================================================= 
# RESTful web service with data as JSON arrays
# =============================================================
.measure_time = function(fun,message,envir=parent.frame()) {
  if (!DEBUG) return(eval(fun,envir = envir))
  tryCatch({
    start = Sys.time()
    eval(fun,envir=envir)
  },finally = {
    cat(message)
    cat("\n")
    print(Sys.time()-start)
  })
}

#* @serializer unboxedJSON 
#* @post /udf
#' UDF on \code{stars} object exposed as a list
#'
#' @param req The incoming HTTP POST request
#'
#' @return The response to the HTTP POST request
#'
#' @description
#' Runs user-defined functions on a \code{stars} object created from JSON arrays
#' exposed as a list to the UDF.
#'
#' This function is linked to the endpoint \code{/udf}
run_UDF.json = function(req,res) {
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
  
  # run the UDF
  stars_out = .measure_time(quote(fun(data=stars_in)),"Executed script. Runtime:")
  #TODO build type related output transformation (user has to define dimensionality)
  # transform stars into JSON
  json_out = .measure_time(quote(stars2json(stars_obj = stars_out, json_in = json_in)),"Translated from stars to list. Runtime:")
  
  json=.measure_time(quote(toJSON(json_out,auto_unbox = TRUE)),"Prepared JSON from list. Runtime:")
  
  if (DEBUG) print(format(Sys.time(),format = "%F %H:%M:%OS"))
  res$body = json
}



# #* @apiTitle R UDF API
# 
# #* Takes a UDFRequest containing data and code and runs the code on the data
# 
# #* @param request
# #* @post /udf
# #* @serializer unboxedJSON
# function(req){
#   browser()
#   list(msg = paste0("Thanks for the data"))
# }
# 
# 

#* Gets the library configuration of this udf service
#* @get /libs
#* @serializer unboxedJSON
get_installed_libraries = function() {
  libs = as.data.frame(installed.packages()[,c("Package","Version")])
  rownames(libs) = NULL

  return(libs)
}
