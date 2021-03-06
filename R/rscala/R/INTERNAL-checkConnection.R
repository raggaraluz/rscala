checkConnection <- function(details) {
  if ( Sys.getpid() != details[["pidOfR"]] ) {
    close.rscalaBridge(details)
    stop("Each process should have its own rscala bridge.  Closing this bridge.")
  }
  if ( details[['closed']] ) stop("Bridge is closed.")
}
