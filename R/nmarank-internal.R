#' @importFrom MASS ginv
#' @importFrom tidyr pivot_longer unite
#' @importFrom stats runif
#' @importFrom rlang is_empty .data
#' @importFrom stats runif
#' @importFrom mvtnorm rmvnorm
#' @importFrom netmeta netmeta
#' @importFrom dplyr %>% filter
#' @importFrom tibble rownames_to_column
#' @importFrom data.tree FromListExplicit


nmaEffects <- function(TE, Cov) {
  
  if (!all(rownames(Cov) == colnames(Cov))) {
    warning(paste("Variance-Covariance matrix Cov should be symmetric",
                  "\n  ",
                  "Please also check row and column names are the same",
                  "\n  ",
                  sep = ""))
  }
  ##
  comps <- rownames(Cov)
  ##
  REs <- TE %>%
    as.data.frame() %>%
    rownames_to_column() %>%
    pivot_longer(cols = -"rowname") %>%
    unite("compname", "rowname", "name", sep = ":") %>%
    filter(.data$compname %in% comps)
  ##
  if ((!all((REs$compname) == rownames(Cov))) | is_empty(REs$value)) {
    stop(paste("Relative Effects and Cov matrix do not match",
                  "\n  ",
                  "Please check treatment labels and dimensions",
                  "\n  ",
                  sep = ""))
  }
  ##
  res <- list(TE = as.matrix(TE), RE = REs$value, Cov = as.matrix(Cov))
  class(res) <- "nmaEffects"
  
  res
}
makeID <- function(op)
  paste(op, as.character(floor(runif(1, 0, 1) * 10000)), sep = "_")


makeNode <- function(selectionList) {
  if (is.null(selectionList$root)) {
    selectionList$id <- makeID(as.character(selectionList$fn))
    selectionList$operation <- "function"
    out <- FromListExplicit(selectionList, nameName = "id")
  }
  else
    out <- selectionList
  
  out
}


selectionHolds <- function(node, small.values, leagueTable) {
  
  if (node$operation == "function")
    return(get(node$fn)(node$args, small.values, leagueTable))
  ##
  if (node$fn == "AND")
    return(
      all(sapply(
        node$children, 
        function(x)
          return(selectionHolds(x, small.values, leagueTable))
      )))
  ##
  if (node$fn == "OR")
    return(
      any(sapply(
        node$children, 
        function(x)
          return(selectionHolds(x,small.values, leagueTable))
      )))
  ##
  if (node$fn == "XOR")
    return(
      xor(selectionHolds(node$children[[1]], small.values, leagueTable),
          selectionHolds(node$children[[2]], small.values, leagueTable)))
  ##
  if (node$fn == "NOT")
    return(
      !(selectionHolds(node$children[[1]], small.values,leagueTable))
    )

  invisible(NULL)
}


setsv <- function(x) {
  if (is.null(x))
    res <- "desirable"
  else {
    res <- setchar(x, c("good", "bad"), stop.at.error = FALSE)
    ##
    if (!is.null(res))
      res <- switch(res, good = "desirable", bad = "undesirable")
    else
      res <- x
  }
  ##
  setchar(res, c("desirable", "undesirable"))
}
