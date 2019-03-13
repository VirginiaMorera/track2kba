## bootstrap     ######################################################################################################

## MAIN UPDATE: tidyverse, simple features
## REVISION: use pre-determined H value for species based on Oppel et al. 2018
## explore whether sequence and number of iterations can be reduced to increase speed
## 1-20 at increments of 1, 20-50 at increments of 3, 50-100 at increments of 5, 100-150 at increments of 10, 150-200 at increments of 25, >200 at increments of 50
## max n iterations to n of possible combinations in data - no need to do 100 iterations if only 20 combinations possible
## explore alternative approach of increasing area of 50%UD (may not be much faster though)

## (Based on original by Phil Taylor & Mark Miller, 2012)

#### DESCRIPTION: ##
## This script iteratively sub-samples a dataset of tracking data, investigating the effect of sample size. 
## This is done by estimating the degree to which the space use of the tracked sample of animals is representative of the population's  
## space use. 
## At each iteration the data is split, one half is used as the 'training' data and the 50%UD is calculated from this. The second half is 
## used as 'testing' data and the proportion of points captured within the 50%UD is calculated.
## A perfect dataset would tend towards 0.5. By fitting a trend line to this relationship we can identify the sample size at which the curve
## approaches an asymptote, signifying that any new data would simply add to existing knowledge. This script produces a 
##representativeness value, indicating how close to this point the sample is. 

#### ARGUMENTS: ##
## DataGroup must be a dataframe or SpatialPointsDataFrame with Latitude, Longitude and ID as fields.
## Scale determines the smoothing factor ('h' parameter) used in the kernel analysis.
## Iteration determines the number of times each sample size is iterated.
## Res sets the resolution of grid cells used in kernel analysis (sq. km)

## REVISED BY Steffen Oppel in 2015 to facilitate parallel processing
## updated to adehabitatHR by Steffen Oppel on 27 Dec 2016
## changed to same4all=TRUE on 4 Feb 2017

## REVISED in 2017 to avoid error in nls function of singular gradient
## added mean output for inclusion value even if nls fails

repAssess <- function(DataGroup, Scale=10, Iteration=50, Res=100, BootTable=T, n.cores=1)
{
  ## do we need rgdal and geosphere? PLEASE CHECK!
  pkgs <-c('sp', 'geosphere', 'adehabitatHR','foreach','doParallel','tidyverse','data.table', 'parallel')
  for(p in pkgs) {suppressPackageStartupMessages(require(p, quietly=TRUE, character.only=TRUE,warn.conflicts=FALSE))}
  
  
  if(!"Latitude" %in% names(DataGroup)) stop("Latitude field does not exist")
  if(!"Longitude" %in% names(DataGroup)) stop("Longitude field does not exist")
  if(!"ID" %in% names(DataGroup)) stop("ID field does not exist")
  
  if(class(DataGroup)!= "SpatialPointsDataFrame")     ## convert to SpatialPointsDataFrame and project
  {
    ## set the minimum fields that are needed
    CleanDataGroup <- DataGroup %>%
      dplyr::select(ID, Latitude, Longitude,DateTime) %>%
      arrange(ID, DateTime)
    mid_point<-data.frame(centroid(cbind(CleanDataGroup$Longitude, CleanDataGroup$Latitude)))
    
    ### PREVENT PROJECTION PROBLEMS FOR DATA SPANNING DATELINE
    if (min(CleanDataGroup$Longitude) < -170 &  max(CleanDataGroup$Longitude) > 170) {
      longs = ifelse(CleanDataGroup$Longitude < 0, CleanDataGroup$Longitude + 360, CleanDataGroup$Longitude)
      mid_point$lon <- ifelse(median(longs) > 180, median(longs) - 360, median(longs))}
    
    DataGroup.Wgs <- SpatialPoints(data.frame(CleanDataGroup$Longitude, CleanDataGroup$Latitude), proj4string=CRS("+proj=longlat + datum=wgs84"))
    proj.UTM <- CRS(paste("+proj=laea +lon_0=", mid_point$lon, " +lat_0=", mid_point$lat, sep=""))
    DataGroup.Projected <- spTransform(DataGroup.Wgs, CRS=proj.UTM )
    TripCoords <- SpatialPointsDataFrame(DataGroup.Projected, data = CleanDataGroup)
    TripCoords@data <- TripCoords@data %>% dplyr::select(ID)
    
  }else{  ## if data are already in a SpatialPointsDataFrame then check for projection
    if(is.projected(DataGroup)){
      TripCoords <- DataGroup
      TripCoords@data <- TripCoords@data %>% dplyr::select(ID)
    }else{ ## project data to UTM if not projected
      mid_point <- data.frame(centroid(cbind(DataGroup@data$Longitude, DataGroup@data$Latitude)))
      
      ### PREVENT PROJECTION PROBLEMS FOR DATA SPANNING DATELINE
      if (min(DataGroup@data$Longitude) < -170 &  max(DataGroup@data$Longitude) > 170) {
        longs = ifelse(DataGroup@data$Longitude < 0, DataGroup@data$Longitude + 360,DataGroup@data$Longitude)
        mid_point$lon<-ifelse(median(longs) > 180, median(longs)-360, median(longs))}
      
      proj.UTM <- CRS(paste("+proj=laea +lon_0=", mid_point$lon, " +lat_0=", mid_point$lat, sep=""))
      TripCoords <- spTransform(DataGroup, CRS=proj.UTM)
      TripCoords@data <- TripCoords@data %>% dplyr::select(ID)
    }
    
  }
  
  proj.UTM <- CRS(proj4string(TripCoords))
  UIDs <- unique(TripCoords$ID)
  NIDs <- length(UIDs)
  
  ### N OF SAMPLE SIZE STEPS NEED TO BE SET DEPENDING ON DATASET - THIS CAN FAIL IF NID falls into a non-existent sequence
  if(NIDs<22){Nloop <- seq(1, (NIDs - 1), 1)}
  if(NIDs>=22 & NIDs<52){Nloop <- c(seq(1, 19, 1), seq(20, (NIDs - 1), 3))}
  if(NIDs>=52 & NIDs<102){Nloop <- c(seq(1, 20, 1), seq(21, 49, 3), seq(50, (NIDs - 1), 6))}
  if(NIDs>=102){Nloop <- c(seq(1, 20, 1), seq(21, 50, 3), seq(51, 99, 6), seq(100, (NIDs - 1), 12))}
  
  DoubleLoop <- data.frame(SampleSize = rep(Nloop, each=Iteration), Iteration=rep(seq(1:Iteration), length(Nloop)))
  LoopNr <- seq(1:dim(DoubleLoop)[1])	
  UDLev <- 50
  
  ### CREATE CUSTOM GRID TO feed into kernelUD (instead of same4all=T)
  minX<-min(coordinates(TripCoords)[,1]) - Scale*2000
  maxX<-max(coordinates(TripCoords)[,1]) + Scale*2000
  minY<-min(coordinates(TripCoords)[,2]) - Scale*2000
  maxY<-max(coordinates(TripCoords)[,2]) + Scale*2000
  
  ### if users do not provide a resolution, then split data into ~500 cells
  if(Res>99){Res <- (max(abs(minX-maxX)/500,
                         abs(minY-maxY)/500))/1000
  warning(sprintf("No grid resolution ('Res') was specified, or the specified resolution was >99 km and therefore ignored. Space use was calculated on a 500-cell grid, with cells of  %s square km.", round(Res,3)),immediate. = TRUE)}
  

  ### specify sequence of grid cells and combine to SpatialPixels
  xrange<-seq(minX,maxX, by = Res*1000) 
  yrange<-seq(minY,maxY, by = Res*1000)
  grid.locs<-expand.grid(x=xrange,y=yrange)
  INPUTgrid<-SpatialPixels(SpatialPoints(grid.locs), proj4string=proj4string(TripCoords))
  
  #### ERROR CATCH IF PEOPLE SPECIFIED TOO FINE RESOLUTION ####
  if (max(length(xrange),length(yrange))>600){warning("Your grid has a pretty large number of cells - this will slow down computation. Reduce 'Res' to speed up the computation.")}
  if (max(length(xrange),length(yrange))>1200){stop("Are you sure you want to run this function at this high spatial resolution ('Res')? Your grid is >1 million pixels, computation will take many hours (or days)!")}
  
  
  
  #########~~~~~~~~~~~~~~~~~~~~~~~~~#########
  ### PARALLEL LOOP OVER AL ITERATIONS ######
  #########~~~~~~~~~~~~~~~~~~~~~~~~~#########
  #before <- Sys.time()
  n.cores<-ifelse(n.cores==1,detectCores()/2,n.cores) ## use user-specified value if provided to avoid computer crashes by using only half the available cores
  cl <- makeCluster(n.cores)  
  registerDoParallel(cl)
  Result <- data.frame()
  
  Result <- foreach(LoopN = LoopNr, .combine = rbind, .packages = c("sp","adehabitatHR","dplyr")) %dopar% {
    
    N <- DoubleLoop$SampleSize[LoopN]
    i <- DoubleLoop$Iteration[LoopN]

    Output <- data.frame(SampleSize = N, InclusionMean = 0,Iteration=i)
    
    RanNum <- sample(UIDs, N, replace=F)
    NotSelected <- TripCoords[!TripCoords$ID %in% RanNum,]
    Selected <- TripCoords[TripCoords$ID %in% RanNum,]
    Selected <- as(Selected, 'SpatialPoints') 

    ##### Calculate Kernel
    
    KDE.Surface <- adehabitatHR::kernelUD(Selected, h=(Scale * 1000), grid=INPUTgrid)
    
    ##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
    ### Calculating inclusion value, using Kernel surface ######
    ##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
    
    KDEpix <- as(KDE.Surface, "SpatialPixelsDataFrame")
    pixArea <- KDE.Surface@grid@cellsize[1]
    
    KDEpix@data <- KDEpix@data %>% 
      rename(UD = ud) %>% 
      mutate(rowname=1:nrow(KDEpix@data)) %>%
      mutate(usage=UD*(pixArea^2)) %>%
      arrange(desc(usage)) %>%
      mutate(cumulUD = cumsum(usage)) %>%
      mutate(INSIDE = ifelse(cumulUD < 0.5, 1, NA)) %>%
      arrange(rowname) %>%
      dplyr::select(INSIDE) 
    
    
    ########
    
    Overlain <- over(NotSelected, KDEpix)
    Output$InclusionMean <- length(which(!is.na(Overlain$INSIDE)))/nrow(NotSelected)
    
    return(Output)
    }
  ## stop the cluster
  on.exit(stopCluster(cl))
  

  if(BootTable==T){
    data.table::fwrite(Result,"bootout_temp.csv", row.names=F, sep=",")
  }
  
  try(M1 <- nls((Result$InclusionMean ~ (a*Result$SampleSize)/(1+b*Result$SampleSize)), data=Result, start=list(a=1,b=0.1)), silent = TRUE)
  if ('M1' %in% ls()){       ### run this only if nls was successful
    Asymptote <- (base::summary(M1)$coefficients[1]/summary(M1)$coefficients[2])
    Result$pred <- stats::predict(M1)
    
    ## Calculate RepresentativeValue 
    RepresentativeValue <- Result %>%
      group_by(SampleSize) %>%
      summarise(out = max(pred) / ifelse(Asymptote < 0.45, 0.5, Asymptote)*100) %>%
      dplyr::filter(out == max(out)) %>%
      mutate(type = ifelse(Asymptote < 0.45, 'asymptote_adj', 'asymptote')) %>%
      mutate(asym = Asymptote) 
    
  if(Asymptote < 0.45 | Asymptote > 60) {
    RepresentativeValue$asym_adj <- 0.5 }
    
    ## Plot
    P2 <- Result %>% 
      group_by(SampleSize) %>% 
      dplyr::summarise(
        meanPred = mean(na.omit(pred)),
        sdInclude = sd(InclusionMean))
    yTemp <- c(P2$meanPred + 0.5 * P2$sdInclude, rev(P2$meanPred - 0.5 * P2$sdInclude))
    xTemp <- c(P2$SampleSize, rev(P2$SampleSize))
    pdf("track2kba_repAssess_output.pdf",width=6, height=5)  ## avoids the plotting margins error
    plot(InclusionMean ~ SampleSize, 
      data = Result, pch = 16, cex = 0.2, col="darkgray", ylim = c(0,1), xlim = c(0,max(unique(Result$SampleSize))), ylab = "Inclusion", xlab = "SampleSize")
    polygon(x = xTemp, y = yTemp, col = "gray93", border = F)
    points(InclusionMean ~ SampleSize, data=Result, pch=16, cex=0.2, col="darkgray")
    lines(P2, lty=1,lwd=2)
    text(x=0, y=1,paste(round(RepresentativeValue$out, 2), "%", sep=""), cex=2, col="gray45", adj=0)  
    dev.off()
  }else{ ### if nls is unsuccessful then use mean output for largest sample size
    RepresentativeValue <- Result %>%
      filter(SampleSize==max(SampleSize)) %>%
      group_by(SampleSize) %>%
      summarise(out=mean(InclusionMean)) %>%
      mutate(type='inclusion')%>%
      mutate(asym=out)
  }
  
  print(ifelse(exists("M1"),"nls (non linear regression) successful, asymptote estimated for bootstrap sample.",
    "WARNING: nls (non linear regression) unsuccessful, likely due to 'singular gradient', which means there is no asymptote. Data may not be representative, output derived from mean inclusion value at highest sample size. Check bootstrap output csv file"))
  
  return(RepresentativeValue)
  
}

