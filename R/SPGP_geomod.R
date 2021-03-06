#' @include GP_geomod.R
NULL

#' Sparse Gaussian Process for Implicit Geological Modeling
#'
#' Implicit geological using Gaussian Processes and compositional relations
#' among the geological classes. Extends the \code{GP_geomod} class.
#'
#' @slot GPs A \code{list} containing one \code{GP} object per class.
#' @slot params A \code{list} containing modeling parameters such as the noise
#' variance and regularization factors.
#'
#' @seealso \code{\link{SPGP_geomod-init}}, \code{\link{GP_geomod-class}}
#'
#' @name SPGP_geomod-class
#' @export SPGP_geomod
SPGP_geomod <- setClass(
  "SPGP_geomod",
  contains = "GP_geomod"
)

#### initialization ####
#' Sparse Gaussian Process for Implicit Geological Modeling
#'
#' Implicit geological using Gaussian Processes and compositional relations
#' among the geological classes.
#'
#' @param data A 3D spatial object.
#' @param value1 A column name indicating the variable that contains the
#' geological classes.
#' @param value2 Another column name, with possibly different class labels.
#' @param model The covariance model. A \code{covarianceStructure3D} or a
#' \code{list} containing one or more such objects.
#' @param nugget The model's nugget effect or noise variance.
#' @param tangents A \code{directions3DDataFrame} object containing structural
#' geology data. Most likely generated with the \code{GetLineDirections()}
#' method.
#' @param pseudo_inputs The desired number of pseudo-inputs (whose coordinates
#' will be sampled from the data) or a matrix or data frame with their
#' coordinates.
#' @param pseudo_tangents The desired number of pseudo-structural data (whose
#' coordinates will be sampled from the data) or a \code{directions3DDataFrame}.
#' @param enforce.contacts Force the model to interpolate geological contacts?
#' @param reg.v Regularization to improve stability. A single value or a vector
#' with length matching the number of data points.
#' @param reg.t Regularization for structural data. A single value or a vector
#' with length matching the number of structural data.
#' @param variational Use the variational approach?
#'
#' @details The role of this class is to manage multiple \code{SPGP} objects, one
#' per geological class in the data, that model an indicator variable or
#' "potential" for each class. A point in 3D space is assigned to the class
#' with the highest modeled potential. The class labels are defined as
#' \code{unique(c(data[[value1]], data[[value2]]))}.
#'
#' The points at which \code{data[[value1]] != data[[value2]]} are considered
#' to lie exactly at a boundary between two geological classes.
#' If \code{enforce.contacts = T}
#' the \code{force.interp} option of the \code{GP} class is turned on in order
#' to make the geological boundaries pass through them.
#'
#' The prediction provides an indicator value for each class at each location,
#' as well as the label of the most likely class. In locations away from the
#' data, the most likely class can be an extra, \code{"Unknown"} class. This
#' class is there to to ensure that the probabilities sum to 1 according to
#' compositional data principles, and also as a measure of model uncertainty.
#'
#' The geological boundaries can be drawn by contouring each class's indicator
#' at the value 0.
#'
#' @seealso \code{\link{SPGP}}, \code{\link{SPGP-init}}, \code{\link{Predict}},
#' \code{\link{Make3DArray}}
#'
#' @name SPGP_geomod-init
#'
#' @references Gonçalves ÍG, Kumaira S, Guadagnin F.
#' A machine learning approach to the potential-field method for implicit
#' modeling of geological structures. Comput Geosci 2017;103:173–82.
#' doi:10.1016/j.cageo.2017.03.015.
SPGP_geomod <- function(data, value1, value2 = value1,
                        model, nugget, tangents = NULL,
                        pseudo_inputs, pseudo_tangents = NULL,
                        variational = T, enforce.contacts = F,
                        reg.v = 1e-9, reg.t = 1e-9){
  # setup
  Ndata <- nrow(data)
  xdata <- GetData(data)
  categories <- c(xdata[, value1], xdata[, value2])
  categories[!is.na(categories)]
  categories <- sort(unique(categories))
  ncat <- length(categories)
  GPs <- vector("list", ncat)

  # model building
  for (i in seq_along(categories)){

    # indicators, or potential components
    ind <- matrix(- 1 / ncat, nrow(data), 2) # negative
    ind[xdata[, value1] == categories[i], 1] <- 1 # positive 1
    ind[xdata[, value2] == categories[i], 2] <- 1 # positive 2
    ind <- rowMeans(ind) # contacts get (1 - 1 / ncat) / 2

    # contact indices
    cont <- ind == (1 - 1/ncat)/2
    if (!enforce.contacts) cont <- numeric()

    # GPs
    GPs[[i]] <- SPGP(data, model,
                     ind,
                     mean = - 1 / ncat,
                     tangents = tangents,
                     reg.t = reg.t,
                     reg.v = reg.v,
                     force.interp = cont,
                     pseudo_inputs = pseudo_inputs,
                     pseudo_tangents = pseudo_tangents,
                     variational = variational)
  }
  names(GPs) <- make.names(categories)

  # output
  new("SPGP_geomod", GPs = GPs,
      params = list(reg.v = reg.v, reg.t = reg.t))
}


#### show ####
setMethod(
  f = "show",
  signature = "SPGP_geomod",
  definition = function(object){
    # display
    cat("Object of class ", class(object), "\n", sep = "")
    cat("Data points:", nrow(object@GPs[[1]]@data), "\n")
    cat("Pseudo-inputs:", nrow(object@GPs[[1]]@pseudo_inputs), "\n")
    Ntang <- ifelse(is.null(object@GPs[[1]]@tangents), 0,
                    nrow(object@GPs[[1]]@tangents))
    cat("Tangent points:", Ntang, "\n")
    cat("Pseudo-tangents:", nrow(object@GPs[[1]]@pseudo_tangents), "\n")
    cat("Number of classes:", length(object@GPs), "\n")
    cat("Log-likelihood:", logLik(object), "\n")
    lab <- names(object@GPs)
    cat("Class labels:\n")
    for (i in seq_along(lab))
      cat("  ", lab[i], "\n")
  }
)


#### summary ####
setMethod(
  f = "summary",
  signature = "SPGP_geomod",
  definition = function(object, ...){
    cat("Object of class ", class(object), "\n", sep = "")
    cat("Data points:", nrow(object@GPs[[1]]@data), "\n")
    cat("Pseudo-inputs:", nrow(object@GPs[[1]]@pseudo_inputs), "\n")
    Ntang <- ifelse(is.null(object@GPs[[1]]@tangents), 0,
                    nrow(object@GPs[[1]]@tangents))
    cat("Tangent points:", Ntang, "\n")
    cat("Pseudo-tangents:", nrow(object@GPs[[1]]@pseudo_tangents), "\n")
    cat("Number of classes:", length(object@GPs), "\n")
    cat("Total Log-likelihood:", logLik(object), "\n\n")
    lab <- names(object@GPs)
    for (i in seq_along(lab)){
      cat("* Class label:", lab[i], "\n")
      gp <- object@GPs[[i]]
      summary(gp)
    }
  }
)

#### Fit ####
#' @rdname Fit
# setMethod(
#   f = "Fit",
#   signature = "SPGP_geomod",
#   definition = function(object, contribution = T, nugget = T, maxrange = T,
#                         midrange = F, minrange = F, azimuth = F, dip = F,
#                         rake = F, power = F, pseudo_inputs = F,
#                         pseudo_tangents = F, ...){
#     lab <- names(object@GPs)
#     for(i in seq_along(object@GPs)){
#       cat("Fitting class", lab[i], "\n\n\n")
#       object@GPs[[i]] <- Fit(object@GPs[[i]], contribution = contribution,
#                              nugget = nugget, maxrange = maxrange,
#                              midrange = midrange, minrange = minrange,
#                              azimuth = azimuth, dip = dip, rake = rake,
#                              power = power,
#                              pseudo_inputs = pseudo_inputs,
#                              pseudo_tangents = pseudo_tangents,
#                              ...)
#     }
#
#     return(object)
#
#   }
# )
setMethod(
  f = "Fit",
  signature = "SPGP_geomod",
  definition = function(object, maxrange = T, midrange = F, minrange = F,
                        azimuth = F, dip = F, rake = F, nugget = F,
                        power = F, ...){

    # setup
    structures <- sapply(object@GPs[[1]]@model@structures, function(x) x@type)
    Nstruct <- length(structures)
    Ndata <- nrow(object@GPs[[1]]@data)
    data_box <- BoundingBox(object@GPs[[1]]@data)
    data_rbase <- sqrt(sum(data_box[1, ] - data_box[2, ])^2)
    GPs <- length(object@GPs)

    # optimization limits and starting point
    opt_min <- opt_max <- numeric(Nstruct * 8 + 1)
    xstart <- matrix(0, 1, Nstruct * 8 + 1)
    for (i in 1:Nstruct){
      # contribution
      opt_min[(i - 1) * 8 + 1] <- 0.1
      opt_max[(i - 1) * 8 + 1] <- 5
      xstart[(i - 1) * 8 + 1] <- object@GPs[[1]]@model@structures[[i]]@contribution

      # maxrange
      if (maxrange){
        opt_min[(i - 1) * 8 + 2] <- data_rbase / 1000
        opt_max[(i - 1) * 8 + 2] <- data_rbase * 5
      }
      else {
        opt_min[(i - 1) * 8 + 2] <- object@GPs[[1]]@model@structures[[i]]@maxrange
        opt_max[(i - 1) * 8 + 2] <- object@GPs[[1]]@model@structures[[i]]@maxrange
      }
      xstart[(i - 1) * 8 + 2] <- object@GPs[[1]]@model@structures[[i]]@maxrange

      # midrange (multiple of maxrange)
      if (midrange)
        opt_min[(i - 1) * 8 + 3] <- 0.01
      else
        opt_min[(i - 1) * 8 + 3] <- 1
      opt_max[(i - 1) * 8 + 3] <- 1
      xstart[(i - 1) * 8 + 3] <- object@GPs[[1]]@model@structures[[i]]@midrange /
        object@GPs[[1]]@model@structures[[i]]@maxrange

      # minrange(multiple of midrange)
      if (minrange)
        opt_min[(i - 1) * 8 + 4] <- 0.01
      else
        opt_min[(i - 1) * 8 + 4] <- 1
      opt_max[(i - 1) * 8 + 4] <- 1
      xstart[(i - 1) * 8 + 4] <- object@GPs[[1]]@model@structures[[i]]@minrange /
        object@GPs[[1]]@model@structures[[i]]@midrange

      # azimuth
      opt_min[(i - 1) * 8 + 5] <- 0
      if (azimuth)
        opt_max[(i - 1) * 8 + 5] <- 360
      else
        opt_max[(i - 1) * 8 + 5] <- 0
      xstart[(i - 1) * 8 + 5] <- object@GPs[[1]]@model@structures[[i]]@azimuth

      # dip
      opt_min[(i - 1) * 8 + 6] <- 0
      if (dip)
        opt_max[(i - 1) * 8 + 6] <- 90
      else
        opt_max[(i - 1) * 8 + 6] <- 0
      xstart[(i - 1) * 8 + 6] <- object@GPs[[1]]@model@structures[[i]]@dip

      # rake
      opt_min[(i - 1) * 8 + 7] <- 0
      if (rake)
        opt_max[(i - 1) * 8 + 7] <- 90
      else
        opt_max[(i - 1) * 8 + 7] <- 0
      xstart[(i - 1) * 8 + 7] <- object@GPs[[1]]@model@structures[[i]]@rake

      # power
      if (power){
        opt_min[(i - 1) * 8 + 8] <- 0.1
        opt_max[(i - 1) * 8 + 8] <- 3
      }
      else{
        opt_min[(i - 1) * 8 + 8] <- 1
        opt_max[(i - 1) * 8 + 8] <- 1
      }
      xstart[(i - 1) * 8 + 8] <- object@GPs[[1]]@model@structures[[i]]@power
    }

    # nugget
    if (nugget){
      opt_min[Nstruct * 8 + 1] <- 1e-6
      opt_max[Nstruct * 8 + 1] <- 2
      xstart[Nstruct * 8 + 1] <- 0.1 #mean(data_nugget)
    }
    else{
      opt_min[Nstruct * 8 + 1] <- object@GPs[[1]]@model@nugget
      opt_max[Nstruct * 8 + 1] <- object@GPs[[1]]@model@nugget
      xstart[Nstruct * 8 + 1] <- object@GPs[[1]]@model@nugget
    }

    # conforming starting point to limits
    xstart[xstart < opt_min] <- opt_min[xstart < opt_min]
    xstart[xstart > opt_max] <- opt_max[xstart > opt_max]

    # fitness function
    makeGP <- function(x, finished = F){
      # covariance model
      m <- vector("list", Nstruct)
      for (i in 1:Nstruct){
        m[[i]] <- covarianceStructure3D(
          type = structures[i],
          contribution = x[( i - 1) * 8 + 1],
          maxrange = x[(i - 1) * 8 + 2],
          midrange = x[(i - 1) * 8 + 2] * x[(i - 1) * 8 + 3],
          minrange = x[(i - 1) * 8 + 2] * x[(i - 1) * 8 + 3] *
            x[(i - 1) * 8 + 4],
          azimuth = x[(i - 1) * 8 + 5],
          dip = x[(i - 1) * 8 + 6],
          rake = x[(i - 1) * 8 + 7],
          power = x[(i - 1) * 8 + 8]
        )
      }
      model <- covarianceModel3D(x[Nstruct * 8 + 1], m)

      # GPs
      tmpgp <- object
      for(i in 1:GPs){
        tmpgp@GPs[[i]] <- SPGP(
          data = tmpgp@GPs[[i]]@data,
          model = model,
          value = "value",
          mean = tmpgp@GPs[[i]]@mean,
          trend = tmpgp@GPs[[i]]@trend,
          tangents = tmpgp@GPs[[i]]@tangents,
          force.interp = tmpgp@GPs[[i]]@data[["interpolate"]],
          pseudo_inputs = object@GPs[[i]]@pseudo_inputs,
          pseudo_tangents = object@GPs[[i]]@pseudo_tangents,
          reg.v = object@GPs[[i]]@pre_comp$reg.v,
          reg.t = object@GPs[[i]]@pre_comp$reg.t,
          variational = object@GPs[[i]]@variational
        )
      }
      # output
      tmpgp@params$nugget <- x[Nstruct * 8 + 1]
      if(finished)
        return(tmpgp)
      else
        return(logLik(tmpgp))
    }

    # optimization
    opt <- GeneticTrainingReal(
      fitness = function(x) makeGP(x, F),
      minval = opt_min,
      maxval = opt_max,
      start = xstart,
      ...
    )

    # update
    sol <- opt$bestsol
    return(makeGP(sol, T))
  }
)
