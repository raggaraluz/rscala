#' Run SBT and Deploy JAR Files
#'
#' This function runs SBT (Scala Build Tool) to package JAR files and then copy
#' them to the appropriate directories of the R package source.
#'
#' Starting from the current working directory and moving up the file system
#' hierarchy as needed, this function searches for the directory containing the
#' file \code{'build.sbt'}, the SBT build file. It temporarily changes the
#' working directory to this directory. Unless the \code{args} argument is
#' overwritten, it then runs \code{sbt +package packageSrc +publishLocal} to
#' package the cross-compiled the Scala code, package the source code, and
#' publish the JAR files locally. Finally, it optionally copies the JAR files to
#' the appropriate directories of the R package source. Specifically, source JAR
#' files go into \code{(PKGHOME)/java} and binary JAR files go into
#' \code{(PKGHOME)/inst/java/scala-(VERSION)}, where \code{(PKGHOME)} is the
#' package home and \code{(VERSION)} is the major Scala version (e.g., 2.12).
#' It is assumed that the package home is a subdirectory of the directory
#' containing the \code{'build.sbt'} file.
#'
#' Note that SBT may give weird errors about not being able to download needed
#' dependences.  The issue is that some OpenJDK builds less than version 10 do
#' not include root certificates.  The solution is to either: i. manually
#' install OpenJDK version 10 or greater, or ii. manually install Oracle's
#' version of Java. Both are capable with the rscala package.
#'
#' @param args A character vector giving the arguments to be passed to the SBT
#'   command.
#' @param copy.to.package Should the JARs files be copied to the appropriate
#'   directories of the R package source?
#' @param use.cache Should compilation be avoided if it appears Scala code
#'   has not changed?
#'
#' @return \code{NULL}
#' @export
scalaSBT <- function(args=c("+package","packageSrc"), copy.to.package=TRUE, use.cache=TRUE) {
  sConfig <- scalaConfig(FALSE,require.sbt=TRUE)
  oldWD <- normalizePath(getwd(),mustWork=FALSE)
  on.exit(setwd(oldWD))
  packageHome <- NULL
  while ( TRUE ) {
    if ( file.exists("DESCRIPTION") ) packageHome <- getwd()
    if ( file.exists("build.sbt") ) break
    currentWD <- getwd()
    setwd("..")
    if ( currentWD == getwd() ) stop("Cannot find 'build.sbt' file.")
  }
  if ( all(grepl("^(\\+?assembly|\\+?package|\\+?packageSrc)$",args)) ) {
    packageHome <- if ( ! is.null(packageHome) ) packageHome
    else {
      descriptionFile <- Sys.glob("*/DESCRIPTION")
      if ( length(descriptionFile) == 1 ) normalizePath(dirname(descriptionFile))
      else if ( length(descriptionFile) == 0 ) {
        descriptionFile <- Sys.glob("*/*/DESCRIPTION")
        if ( length(descriptionFile) == 1 ) normalizePath(dirname(descriptionFile))
        else NULL
      } else NULL
    }
    latest <- function(path,pattern=NULL) {
      files <- list.files(path, pattern=pattern, recursive=TRUE, full.names=TRUE)
      xx <- sapply(files, function(f) { file.info(f)$mtime })
      if ( length(xx) == 0 ) -Inf else max(xx)
    }
    srcHome <- "src"
    if ( use.cache && file.exists(srcHome) && !is.null(packageHome) && file.exists(packageHome) && ( latest(srcHome) < latest(packageHome,'.*\\.jar') ) ) {
      cat("[info] Latest Scala source is older that JARs.  There is no need to re-compile.\n")
      return(invisible())
    }
  }
  oldJavaEnv <- setJavaEnv(sConfig)
  status <- system2(path.expand(sConfig$sbtCmd),args)
  setJavaEnv(oldJavaEnv)
  if ( status != 0 ) stop("Non-zero exit status.") 
  if ( copy.to.package ) {
    lines <- readLines("build.sbt")
    nameLine <- lines[grepl("^\\s*name\\s*:=",lines)]
    if ( length(nameLine) != 1 ) stop("Could not find one and only one 'name' line in 'build.sbt'.")
    name <- sub('^[^"]*"(.*)"[,\\s]*$','\\1',nameLine)
    versionLine <- lines[grepl("^\\s*version\\s*:=",lines)]
    if ( length(versionLine) != 1 ) stop("Could not find one and only one 'version' line in 'build.sbt'.")
    version <- sub('^[^"]*"(.*)"[,\\s]*$','\\1',versionLine)
    scalaVersionLine <- lines[grepl("^\\s*scalaVersion\\s*:=",lines)]
    if ( length(scalaVersionLine) != 1 ) stop("Could not find one and only one 'scalaVersion' line in 'build.sbt'.")
    scalaVersion <- scalaMajorVersion(sub('^[^"]*"(.*)"[,\\s]*$','\\1',scalaVersionLine))
    crossLine <-   lines[grepl("^\\s*crossScalaVersions\\s*:=",lines)]
    if ( length(crossLine) != 1 ) stop("Could not find one and only one 'crossScalaVersion' line in 'build.sbt'.")
    scalaVersions <- strsplit(gsub('["),]','',sub('[^"]*','',crossLine)),"\\s+")[[1]]
    scalaVersions <- sapply(scalaVersions, function(x) {
      if ( grepl("^2.1[12]\\.",x) ) substr(x,1,4) else x
    })
    if ( is.null(sConfig$sbtCmd) ) {
      stopMsg <- "\n\n<<<<<<<<<<\n<<<<<<<<<<\n<<<<<<<<<<\n\nSBT is not found!  Please run 'rscala::scalaConfig(require.sbt=TRUE)'\n\n>>>>>>>>>>\n>>>>>>>>>>\n>>>>>>>>>>\n"
      stop(stopMsg)
    }
    srcJARs <- paste0("scala-",scalaVersions,"/",tolower(name),"_",scalaVersions,"-",version,"-sources.jar")
    if ( any(grepl("^\\+?assembly$",args)) ) {
      binJARs <- paste0("scala-",scalaVersions,"/",name,"-assembly-",version,".jar")
    } else {
      binJARs <- paste0("scala-",scalaVersions,"/",tolower(name),"_",scalaVersions,"-",version,".jar")
    }
    pkgHome <- unique(dirname(list.files(".","DESCRIPTION",recursive=TRUE)))   # unique(...) because on Mac OS X, duplicates are possible.
    pkgHome <- pkgHome[!grepl(".*\\.Rcheck",pkgHome)]
    if ( length(pkgHome) > 1 ) {
      if ( sum(normalizePath(pkgHome,mustWork=FALSE)==oldWD) == 1 ) pkgHome <- pkgHome[normalizePath(pkgHome,mustWork=FALSE)==oldWD]
      else {
        if ( sum(basename(pkgHome)==name) == 1 ) pkgHome <- pkgHome[basename(pkgHome)==name]
        else stop(paste0("Cannot determine package home among: ",paste(pkgHome,collapse="  ")))
      }
    } else if ( length(pkgHome) == 0 ) stop(paste0("Cannot find any candidates for package home."))
    binDir <- file.path(pkgHome,"inst","java")
    oldDirs <- list.files(binDir,"^scala-.*")
    unlink(file.path(binDir,oldDirs),recursive=TRUE)
    for ( v in scalaVersions ) {
      currentJARs <- binJARs[grepl(sprintf("^scala-%s",v),binJARs)]
      currentJARs <- currentJARs[grepl(sprintf(".*-%s.jar$",version),basename(currentJARs))]
      if ( length(currentJARs) > 0 ) {
        destDir <- file.path(binDir,sprintf("scala-%s",v))
        dir.create(destDir,FALSE,TRUE)
        file.copy(file.path("target",currentJARs),destDir,TRUE)
      }
    }
    srcDir <- file.path(pkgHome,"java")
    unlink(list.files(srcDir,pattern=".*\\.jar",recursive=TRUE,full.names=TRUE))
    dir.create(srcDir,FALSE,TRUE)
    currentJARs <- srcJARs[grepl(sprintf("^scala-%s",scalaVersion),srcJARs)]
    currentJARs <- currentJARs[grepl(sprintf(".*_%s-%s-sources.jar$",scalaVersion,version),basename(currentJARs))]
    if ( length(currentJARs) > 0 ) file.copy(file.path("target",currentJARs),srcDir,TRUE)
  }
  invisible(NULL)
}
