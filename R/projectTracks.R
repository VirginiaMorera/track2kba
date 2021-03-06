## projectTracks ###############################################################

#' Project tracking data
#'
#' \code{projectTracks} Projects tracking data to a custom lambert equal-area 
#' projection for use in kernel density analysis.
#'
#' @param dataGroup data.frame or SpatialPointsDataFrame. Tracking data, with fields as named by 
#' \code{\link{formatFields}}.
#' @param reproject logical (TRUE/FALSE). If your dataGroup dataframe is already
#'  projected, would you like to reproject these to a custom equal-area 
#'  projection?
#' 
#' Input data can be tracks split into trips (i.e. output of 
#' \code{\link{tripSplit}}).
#' 
#' Data are transformed to a lambert equal-area projection with it's center 
#' determined by the data. Data must contain 'Latitude' and 'Longitude' columns.
#'  Note that this projection may not be the most appropriate for your data and 
#'  it is almost certainly better to identify a projection appropriate for you 
#'  study region. So it is not strictly necessary for \code{projectTracks} to be
#'   used in track2KBA analysis, what is important is that an equal-area 
#'   projection of some kind is used when constructing kernel density estimates.
#' 
#' @return Returns a SpatialPointsDataFrame, which can be used for the following
#'  functions: \code{\link{findScale}}, \code{\link{estSpaceUse}}, 
#'  \code{\link{indEffectTest}}, \code{\link{repAssess}} .
#'
#' @seealso \code{\link{tripSummary}}
#'
#' @examples
#' \dontrun{
#' 
#' data(boobies)
#' 
#' tracks <- formatFields(boobies, BLformat=TRUE)
#' 
#' tracks_prj <- project(tracks)
#' 
#' }
#'
#' @export

projectTracks <- function(dataGroup, reproject=FALSE){
  
  mid_point <- data.frame(
    geosphere::centroid(cbind(dataGroup$Longitude, dataGroup$Latitude))
    )
  proj <- CRS(
    paste(
      "+proj=laea +lon_0=", mid_point$lon, 
      " +lat_0=", mid_point$lat, sep=""
      )
    )
  
  if(class(dataGroup)!= "SpatialPointsDataFrame") {

    ### PREVENT PROJECTION PROBLEMS FOR DATA SPANNING DATELINE ----------------
    if (min(dataGroup$Longitude) < -170 & max(dataGroup$Longitude) > 170) {
      longs <- ifelse(
        dataGroup$Longitude < 0, dataGroup$Longitude + 360, dataGroup$Longitude
        )
      mid_point$lon <- ifelse(
        median(longs) > 180, median(longs) - 360, median(longs)
        )
      }
    
    dataGroup.Wgs <- SpatialPoints(
      data.frame(dataGroup$Longitude, dataGroup$Latitude), 
      proj4string=CRS(SRS_string = "EPSG:4326")
      )
    Tracks_prj <- spTransform(dataGroup.Wgs, CRSobj=proj )
    Tracks_prj <- SpatialPointsDataFrame(Tracks_prj, data = dataGroup)
    
  } else if(is.projected(dataGroup) & reproject == FALSE){
    Tracks_prj <- dataGroup
    message("if you wish to reproject these data to custom equal-area projection
      set reproject=TRUE")
  } else { 
    ## if SPDF and not projected, project -------------------------------------
    ### PREVENT PROJECTION PROBLEMS FOR DATA SPANNING DATELINE ---------------
    if (
      min(dataGroup@data$Longitude) < -170 & max(dataGroup@data$Longitude) > 170
      ) {
      longs <- ifelse(
        dataGroup@data$Longitude < 0, 
        dataGroup@data$Longitude + 360, dataGroup@data$Longitude
        )
      mid_point$lon <- ifelse(
        median(longs) > 180, median(longs) - 360, median(longs)
        )
      }
    
    Tracks_prj <- sp::spTransform(dataGroup, CRSobj=proj)
  }
  return(Tracks_prj)
}
