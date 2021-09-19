#' Probabilities of treatment hierarchies
#'
#' @description
#' Specifies the frequencies of hierarchies along with their estimated
#' probabilities and the probability that a specified criterion holds.
#'
#' @details
#' A simulation method is used to derive the relative frequency of all possible
#' hierarchies in a network of interventions. Users can also define the set of all
#' possible hierarchies that satisfy a specified criterion, for example that a
#' specific order among treatments is retained in the network and/or a treatment
#' is in a specific position, and the sum of their frequencies constitute the
#' certainty around the criterion. 
#'
#' @param TE.nma Either a \code{\link{netmeta}} object or a matrix
#'   with network estimates.
#' @param condition Defines the conditions that should be satisfied
#' by the treatments in the network. Multiple conditions can be combined with
#' special operators into any decision tree. See \code{\link{condition}}.
#' @param text.condition Optional descriptive text for the condition.
#' @param VCOV.nma Variance-covariance matrix for network estimates
#'   (only considered if argument \code{TE.nma} isn't a
#'   \code{\link{netmeta}} object).
#' @param pooled A character string indicating whether the hierarchy
#'   is calculated for the fixed effects (\code{"fixed"}) or random
#'   effects model (\code{"random"}). Can be abbreviated.
#' @param nsim Number of simulations.
#' @param small.values A character string specifying whether small
#'   treatment effects indicate a "good" or "bad" effect.
#' @param x A \code{\link{nmarank}} object.
#' @param nrows Number of hierarchies to print.
#' @param digits Minimal number of significant digits for proportions,
#'   see \code{print.default}.
#' @param \dots Additional arguments.
#' 
#' @return
#' An object of class \code{"nmarank"} with corresponding \code{print}
#' function. The object is a list containing the following components:
#'
#' \item{hierarchies}{A list of the most frequent hierarchies along
#'  with their estimated probability of occurrence.}
#' \item{probabilityOfSelection}{Combined probability of all
#'   hierarchies that satisfy the defined condition.}
#' \item{TE.nma, condition, VCOV.nma,}{As defined above.}
#' \item{pooled, nsim, small.values}{As defined above.}
#'
#' @import netmeta mvtnorm dplyr tibble data.tree
#' 
#' @examples
#' data("Woods2010", package = "netmeta")
#' p1 <- pairwise(treatment, event = r, n = N, studlab = author,
#'                data = Woods2010, sm = "OR")
#' net1 <- netmeta(p1, small.values = "good")
#'
#' nmarank(net1, nsim = 100)
#'
#' criterionA <-
#'  condition("sameHierarchy",
#'            c("SFC", "Salmeterol", "Fluticasone", "Placebo"))
#' nmarank(net1, criterionA, nsim = 100)
#'
#' @seealso \code{\link{condition}}, \code{\link[netmeta]{netmeta}}
#' 
#' @export


nmarank <- function(TE.nma, condition=NULL, text.condition = "",
                    VCOV.nma = NULL, pooled,
                    nsim = 10000, small.values) {
  
  if (inherits(TE.nma, "netmeta")) {
    if (!is.null(VCOV.nma))
      warning("Argument 'VCOV.nma' ignored for objects of type 'netmeta'.",
              call. = FALSE)
    ##
    if (missing(small.values))
      small.values <- TE.nma$small.values
    ##
    if (missing(pooled))
      if ((TE.nma$comb.fixed == FALSE) |
          (TE.nma$comb.fixed == TRUE & TE.nma$comb.random == TRUE)) {
        pooled <- "random"
        VCOV.nma <- TE.nma$Cov.random
        TE.nma <- TE.nma$TE.random
      }
      else {
        pooled <- "fixed"
        VCOV.nma <- TE.nma$Cov.fixed
        TE.nma <- TE.nma$TE.fixed
      }
  }
  else {
    if (is.null(VCOV.nma))
      warning("Argument 'VCOV.nma' must be provided as ",
              "'TE.nma' isn't a 'netmeta' object.",
              call. = FALSE)
    ##
    if (missing(small.values))
      small.values <- "bad"
    ##
    if (missing(pooled))
      pooled <- ""
  }
  ##
  if (is.null(condition)){
    condition <- condition("alwaysTRUE")
  }
  ##
  effects <- nmaEffects(TE.nma, VCOV.nma)
  ##
  TEs <- effects$TE
  REs <- effects$RE
  Covs <- effects$Cov
  ##
  small.values <- setchar(small.values, c("bad", "good"))
  pooled <- setchar(pooled, c("fixed", "random", ""))
  ##
  trts <- rownames(TEs)
  ##
  if (condition$fn == "sameHierarchy") {
    condition$args[[1]] <-
      setseq(condition$args[[1]], trts,
             error.text =
               paste0("first argument of condition \"",
                      condition$fn, "\""))
  }
  else if (condition$fn == "retainOrder")
    condition$args[[1]] <-
      setref(condition$args[[1]], trts, length = 0,
             error.text =
               paste0("first argument of condition \"",
                      condition$fn, "\""))
  else if (condition$fn %in%
           c("specificPosition", "betterEqual", "biggerCIV")) {
    condition$args[[1]] <-
      setref(condition$args[[1]], trts, length = 1,
             error.text =
               paste0("first argument of condition \"",
                      condition$fn, "\""))
    ##
    if (condition$fn %in% c("specificPosition", "betterEqual"))
      chknumeric(condition$args[[2]], min = 1, max = length(trts),
                 text = paste0("Second argument of condition \"",
                               condition$fn, "\" ",
                               "must be a single numeric ",
                               "between 1 and ", length(trts),
                               "."))
    ##
    if (condition$fn == "biggerCIV") {
      condition$args[[2]] <-
        setref(condition$args[[2]], trts, length = 1,
               error.text =
                 paste0("second argument of condition \"",
                        condition$fn, "\""))
    }
  }
  
  
  leagueTableFromRelatives <- function(rels) {
    lgtbl <- matrix(0, nrow = nrow(TEs), ncol = ncol(TEs),
                    dimnames = list(rownames(TEs), colnames(TEs)))
    ##
    lgtbl[lower.tri(lgtbl)] <- rels
    lgtbl <- t(lgtbl)
    lgtbl[lower.tri(lgtbl)] <- -rels
    lgtbl
  }
  
  
  if (is.null(condition$root))
    condition <- makeNode(condition)
  
  
  rels <- mvtnorm::rmvnorm(nsim, REs, Covs, checkSymmetry = FALSE)
  
  
  hitsranks <-
    Reduce(function(acc, i) {
      x <- rels[i, ]
      leagueT <- leagueTableFromRelatives(x)
      if (selectionHolds(condition, small.values, leagueT))
        newhits <- acc$hits + 1
      else
        newhits <- acc$hits
      ##
      thisrank <- getRank(leagueT, small.values) %>% paste(collapse = ", ")
      newranks <- acc$ranks
      if (is.null(acc$ranks[thisrank]))
        newranks[thisrank] <- 1
      else {
        if (is.na.data.frame(acc$ranks[thisrank]))
          newranks[thisrank] <- 1
        else
          newranks[thisrank] <- newranks[thisrank] + 1
      }
      ##
      list(hits = newhits, ranks = newranks)
    },
    1:nsim, list(hits = 0, ranks = c()))
  ##
  hitsranks$ranks <- sort(hitsranks$ranks, decreasing = TRUE)
  ##
  ranks <- data.frame(Hierarchy = hitsranks$ranks %>% names(),
                      Probability = hitsranks$ranks / nsim,
                      row.names = seq_along(hitsranks$ranks))
  
  
  res <- list(hierarchies = ranks,
              probabilityOfSelection = hitsranks$hits / nsim,
              TE.nma = TE.nma, VCOV.nma = VCOV.nma,
              pooled = pooled, nsim = nsim, small.values = small.values,
              condition = condition, text.condition = text.condition)
  ##
  class(res) <- "nmarank"
  
  res
}


#' @rdname nmarank
#' @method print nmarank
#'
#' @importFrom meta gs
#' 
#' @export
#' @export print.nmarank

print.nmarank <- function(x, text.condition = x$text.condition,
                          nrows = 10,
                          digits = gs("digits.prop"), ...) {
  if (x$pooled == "random")
    text.pooled <- " (random effects model)"
  else if (x$pooled == "fixed")
    text.pooled <- " (fixed effects model)"
  else
    text.pooled <- ""
  ##
  cat(paste0("Treatment hierarchy", text.pooled, "\n\n"))

  if (x$condition$fn == "alwaysTRUE") {
    x$hierarchies$Probability <-
      formatN(x$hierarchies$Probability, digits = digits)
    print(x$hierarchies[seq_len(min(nrow(x$hierarchies), nrows)), ], ...)
    if (nrows < nrow(x$hierarchies))
      cat("...\n")
  }
  else if (x$condition$fn == "sameHierarchy")
    cat(paste0("Probability of hierarchy '",
               paste(x$condition$args[[1]], collapse = ", "),
               "': ",
               x$probabilityOfSelection %>% formatN(digits = digits),
               "\n"))
  else if (x$condition$fn == "retainOrder")
    cat(paste0("Probability that order '",
               paste(x$condition$args[[1]], collapse = ", "),
               "' is retained anywhere in the hierarchy: ",
               x$probabilityOfSelection %>% formatN(digits = digits),
               "\n"))
  else if (x$condition$fn == "specificPosition")
    cat(paste0("Probability that '",
               x$condition$args[[1]],
               "' is at rank position ", x$condition$args[[2]],
               ": ",
               x$probabilityOfSelection %>% formatN(digits = digits),
               "\n"))
  else if (x$condition$fn == "betterEqual")
    cat(paste0("Probability that '",
               x$condition$args[[1]],
               "' is among the best ",
               if (x$condition$args[[2]] <= 10)
                 c("two", "three", "four",
                   "five", "six", "seven", "eight", "nine",
                   "ten")[match(x$condition$args[[2]], 2:10)]
               else
                 x$condition$args[[2]],
               " options: ",
               x$probabilityOfSelection %>% formatN(digits = digits),
               "\n"))
  else if (x$condition$fn == "biggerCIV")
    cat(paste0("Probability that '",
               x$condition$args[[1]],
               "' is better than '", x$condition$args[[2]],
               "' by more than ",
               x$condition$args[[3]],
               " (CIV): ",
               x$probabilityOfSelection %>% formatN(digits = digits),
               "\n"))
  else
    cat(paste0("Probability", if (text.condition != "") " that ",
               text.condition,
               ": ",
               x$probabilityOfSelection %>% formatN(digits = digits),
               "\n"))
  ##
  invisible(NULL)
}