## estSpaceUse  #####################################################################################################################

#' Estimate the space use of tracked animals using kernel utilization distribution
#'
#' \code{estSpaceUse} is a wrapper for \code{\link{kernelUD}} which estimates the utilization distribution (UD) of multiple individuals or tracks in a tracking dataset.
#'
#' A utilization distribution will be calculated for each unique 'ID'. The data should be regularly sampled or interpolated (see adehabitatLT package for functions to this end).
#'
#' @param DataGroup data.frame or SpatialPointsDataFrame. Must have an 'ID' field; if input is data.frame or unprojected SpatialPointsDF, must also include 'Latitude' and 'Longitude' fields. For formatting issues see \code{\link{formatFields}}.
#' @param Scale numeric (in kilometers). The smoothing parameter ('H') used in the kernel density estimation, which defines the width of the normal distribution around each location. The \code{\link{findScale}} function can assist in finding sensible scales.
#' @param UDLev numeric (percent). Specify which utilization distribution contour to show in the plotted output. NOTE: this will only affect the output if \code{polyOut=TRUE}.
#' @param Res numeric (in kilometers). Grid cell resolution (in square kilometers) for kernel density estimation. Default is a grid of 500 cells, with spatial extent determined by the latitudinal and longitudinal extent of the data.
#' @param polyOut logical scalar (TRUE/FALSE). If TRUE then output will include a plot of individual UD polygons and a simple feature with kernel UD polygons for the level of \code{UDLev}. NOTE: creating polygons of UD is both computationally slow and prone to errors if the usage included in \code{UDLev} extends beyond the specified grid. In this case \code{estSpaceUse} will return only the \code{estUDm}object and issue a warning.
#'
#' @return Returns an object of class \code{estUDm} which is essentially a list, with each item representing the utilization distribution of a level of 'ID'. Values in the output signify the usage probability per unit area for that individual in each grid cell. This can be converted into a SpatialPixelsDataFrame via the \code{\link[adehabitatHR]{estUDm2spixdf}} function.
#'
#' If \code{polyOut=TRUE} the output will be a list with two components: \emph{'KDE.Surface'} is the \code{estUDm} object and \code{UDPolygons} is polygon object of class \code{sf} (Simple Features) with the UD contour for each individual at the specified \code{UDLev}.
#'
#' If \code{polyOut=TRUE} but the polygon delineation in \code{adehabitatHR::getverticeshr} fails, output is an object of class \code{estUDm} and a warning will be issued.
#'
#' @seealso \code{\link{formatFields}}, \code{\link{tripSplit}}, \code{\link{findScale}}
#'
#' @examples
#' \dontrun{UDs <- estSpaceUse(DataGroup=Trips, Scale = HVALS$mag, UDLev = 50, polyOut=T)}
#'
#' @export
#' @import sf
#' @import sp
#' @import adehabitatHR

estSpaceUse <- function(DataGroup, Scale = 50, UDLev = 50, Res=1000, polyOut=FALSE)
{
  pkgs <-c('sp', 'tidyverse', 'geosphere', 'adehabitatHR')
  for(p in pkgs) {suppressPackageStartupMessages(require(p, quietly=TRUE, character.only=TRUE,warn.conflicts=FALSE))}
  
  if(!"ID" %in% names(DataGroup)) stop("ID field does not exist")
  
  ##~~~~~~~~~~~~~~~~~~~~~~~~##
  ###### DATA PREPARATION ####
  ##~~~~~~~~~~~~~~~~~~~~~~~~##
  ## kernelUD requires a SpatialPointsDataFrame in a projected equal-area CRS as input
  ## we create a SPDF called 'TripCoords' in a projected CRS either from raw data or an existing SPDF
  ## only column in @dat should be the 'ID' field
  
  
  if(class(DataGroup)!= "SpatialPointsDataFrame")     ## convert to SpatialPointsDataFrame and project
  {
    if(!"Latitude" %in% names(DataGroup)) stop("Latitude field does not exist")
    if(!"Longitude" %in% names(DataGroup)) stop("Longitude field does not exist")
    ## set the minimum fields that are needed
    CleanDataGroup <- DataGroup %>%
      dplyr::select(.data$ID, .data$Latitude, .data$Longitude, .data$DateTime) %>%
      arrange(.data$ID, .data$DateTime)
    mid_point <- data.frame(geosphere::centroid(cbind(CleanDataGroup$Longitude, CleanDataGroup$Latitude)))
    
    ### PREVENT PROJECTION PROBLEMS FOR DATA SPANNING DATELINE
    if (min(CleanDataGroup$Longitude) < -170 &  max(CleanDataGroup$Longitude) > 170) {
      longs = ifelse(CleanDataGroup$Longitude < 0, CleanDataGroup$Longitude + 360, CleanDataGroup$Longitude)
      mid_point$lon <- ifelse(median(longs) > 180, median(longs)-360, median(longs))}
    
    DataGroup.Wgs <- SpatialPoints(data.frame(CleanDataGroup$Longitude, CleanDataGroup$Latitude), proj4string=CRS("+proj=longlat + datum=wgs84"))
    proj.UTM <- CRS(paste("+proj=laea +lon_0=", mid_point$lon, " +lat_0=", mid_point$lat, sep=""))
    DataGroup.Projected <- spTransform(DataGroup.Wgs, CRS=proj.UTM )
    TripCoords <- SpatialPointsDataFrame(DataGroup.Projected, data = CleanDataGroup)
    TripCoords@data <- TripCoords@data %>% dplyr::select(.data$ID)
    DataGroup.Wgs<-NULL
    DataGroup.Projected<-NULL
    
  }else{  ## if data are already in a SpatialPointsDataFrame then check for projection
    if(is.projected(DataGroup)){
      if("trip_id" %in% names(DataGroup@data)){
        TripCoords <- DataGroup[DataGroup$trip_id != "-1",]}else{      ## make sure to remove locations not associated with a trip
          TripCoords <- DataGroup}
      TripCoords@data <- TripCoords@data %>% dplyr::select(.data$ID)
    }else{ ## project data to UTM if not projected
      
      if(!"Latitude" %in% names(DataGroup)) stop("Latitude field does not exist")
      if(!"Longitude" %in% names(DataGroup)) stop("Longitude field does not exist")
      mid_point<-data.frame(centroid(cbind(DataGroup@data$Longitude, DataGroup@data$Latitude)))
      
      ### PREVENT PROJECTION PROBLEMS FOR DATA SPANNING DATELINE
      if (min(DataGroup@data$Longitude) < -170 &  max(DataGroup@data$Longitude) > 170) {
        longs=ifelse(DataGroup@data$Longitude<0,DataGroup@data$Longitude+360,DataGroup@data$Longitude)
        mid_point$lon<-ifelse(median(longs)>180,median(longs)-360,median(longs))}
      
      proj.UTM <- CRS(paste("+proj=laea +lon_0=", mid_point$lon, " +lat_0=", mid_point$lat, sep=""))
      TripCoords <- spTransform(DataGroup, CRS=proj.UTM)
      TripCoords@data <- TripCoords@data %>% dplyr::select(.data$ID)
    }
    
  }
  DataGroup<-NULL
  gc()
  
  ##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
  ###### REMOVING IDs WITH TOO FEW LOCATIONS ####
  ##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
  ###### ENSURE THAT kernelUD does not fail by retaining ONLY TRACKS WITH 5 OR MORE LOCATIONS
  validIDs <- names(which(table(TripCoords$ID)>5))
  TripCoords<-TripCoords[(TripCoords@data$ID %in% validIDs),]
  TripCoords@data$ID<-droplevels(as.factor(TripCoords@data$ID))        ### encountered weird error when unused levels were retained (27 Feb 2017)
  
  
  ##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
  ###### SETTING PARAMETERS FOR kernelUD : THIS NEEDS MORE WORK!! ####
  ##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
  
  ### CREATE CUSTOM GRID TO feed into kernelUD (instead of same4all=T)
  ### NEED TO DO: link resolution of grid to H-parameter ('Scale')
  
  minX<-min(coordinates(TripCoords)[,1]) - Scale*2000
  maxX<-max(coordinates(TripCoords)[,1]) + Scale*2000
  minY<-min(coordinates(TripCoords)[,2]) - Scale*2000
  maxY<-max(coordinates(TripCoords)[,2]) + Scale*2000
  
  ### if users do not provide a resolution, then split data into ~500 cells
  if(Res>99){Res<- (max(abs(minX-maxX)/500,
    abs(minY-maxY)/500))/1000
  warning(sprintf("No grid resolution ('Res') was specified, or the specified resolution was >99 km and therefore ignored.
    Space use was calculated on a 500-cell grid, with cells of %s square km", round(Res,3)),immediate. = TRUE)}
  
  ### specify sequence of grid cells and combine to SpatialPixels
  xrange <- seq(minX,maxX, by = Res*1000) #diff(range(coordinates(TripCoords)[,1]))/Res)   ### if Res should be provided in km we need to change this
  yrange <- seq(minY,maxY, by = Res*1000) #diff(range(coordinates(TripCoords)[,2]))/Res)   ### if Res should be provided in km we need to change this
  grid.locs <- expand.grid(x=xrange,y=yrange)
  INPUTgrid <- SpatialPixels(SpatialPoints(grid.locs), proj4string=proj4string(TripCoords))
  #  plot(INPUTgrid)
  
  #### ERROR CATCH IF PEOPLE SPECIFIED TOO FINE RESOLUTION ####
  if (Scale<Res*0.1228){warning("Your scale parameter is very small compared to the grid resolution - 99.99% of the kernel density for a given location will be within a single grid cell, which will limit the amount of overlap of different individual's core use areas. Increase 'Scale' or reduce 'Res' to avoid this problem.",immediate. = TRUE)}
  if (max(length(xrange),length(yrange))>600){warning("Your grid has a pretty large number of cells - this will slow down computation. Increase 'Res' (= make the grid cells larger) to speed up the computation.",immediate. = TRUE)}
  if (max(length(xrange),length(yrange))>1200){stop("Are you sure you want to run this function at this high spatial resolution (= very small grid cell size specified in 'Res')? Your grid is >1 million pixels, computation will take many hours (or days)!")}
  
  
  
  ##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
  ###### ESTIMATING KERNEL DISTRIBUTION  ####
  ##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
  ## may need to insert extent=BExt, but hopefully avoided by custom-specified grid
  ## switched from same4all=T to =F because we provide a fixed input grid
  
  KDE.Surface <- adehabitatHR::kernelUD(TripCoords, h=(Scale * 1000), grid=INPUTgrid, same4all=F)
  
  
  ##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
  ###### OPTIONAL POLYGON OUTPUT ####
  ##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
  if(polyOut==TRUE){
    pkgs <- c('sf', 'ggplot2')
    for(p in pkgs) {suppressPackageStartupMessages(require(p, quietly=TRUE, character.only=TRUE,warn.conflicts=FALSE))}
    
    tryCatch({
      KDE.Sp <- adehabitatHR::getverticeshr(KDE.Surface, percent = UDLev,unin = "m", unout = "km2")
    }, error=function(e){
      sprintf("Providing individual home range polygons at a UD level of %s percent failed with the following error message: %s. This means that there was estimated space use that extended beyond the grid used for estimating the kernel density. To resolve this, use a lower UD level, or a smaller Scale parameter.", UDLev,conditionMessage(e))})
    
    if(('KDE.Sp' %in% ls())){     ## PROCEED ONLY IF KDE.Sp was successfully created
      
      HR_sf <- st_as_sf(KDE.Sp) %>%
        st_transform(4326) ### convert to longlat CRS
      
      ### ADD A PLOT OF THE CORE RANGES ##
      coordsets <- st_bbox(HR_sf)
      UDPLOT <- ggplot(HR_sf) + geom_sf(data=HR_sf, aes(col=id), fill=NA) +
        coord_sf(xlim = c(coordsets$xmin, coordsets$xmax), ylim = c(coordsets$ymin, coordsets$ymax), expand = FALSE) +
        borders("world",fill="dark grey",colour="grey20") +
        theme(panel.background=element_rect(fill="white", colour="black"),
          axis.text=element_text(size=16, color="black"),
          axis.title=element_text(size=16),
          legend.position = "none") +
        ylab("Longitude") +
        xlab("Latitude")
      print(UDPLOT)
      return(list(KDE.Surface=KDE.Surface, UDPolygons=HR_sf))
      
    }else{
      warning(sprintf("Providing individual home range polygons at a UD level of %s percent failed. This often means that there was estimated space use that extended beyond the grid used for estimating the kernel density. To resolve this, use a lower UD level, a smaller Scale parameter, or a smaller size of grid cells (smaller 'Res'). However, the same error may occur if your Scale parameter is very small (compared to 'Res'), because the grid is extended beyond the bounding box of locations by a distance of 2*Scale - and with a very small Scale parameter that may not actually encompass a full grid cell. ", UDLev),immediate. = TRUE)
      return(KDE.Surface)}
    
  }else{
    return(KDE.Surface)
  }  ## changed from KDE.Spdf to replace with cleaned version
  }
