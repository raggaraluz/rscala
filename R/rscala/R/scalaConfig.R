#' Configure Scala and Java
#'
#' This function installs Scala and/or Java in the user's \code{~/.rscala}
#' directory.
#'
#' @param verbose Should details of the search for Scala and Java be provided?
#'   Or, if an rscala bridge is provided instead of a logical, the function
#'   returns a list of details associated with the supplied bridge.
#' @param reconfig If \code{TRUE}, the script \code{~/.rscala/config.R} is
#'   rewritten based on a new search for Scala and Java.  If \code{FALSE}, the
#'   previous configuration is sourced from the script
#'   \code{~/.rscala/config.R}.  If \code{"live"}, a new search is performed,
#'   but the results do not overwrite the previous configuration script.  Finally,
#'   the value set here is superceded by the value of the environment variable
#'   \code{RSCALA_RECONFIG}, if it exists.
#' @param download A character vector which may be length-zero or whose elements
#'   are any combination of \code{"java"}, \code{"scala"}, or \code{"sbt"}. Or,
#'   \code{TRUE} denotes all three.  The indicated software will be installed at
#'   "~/.rscala".
#' @param require.sbt Should SBT be required, downloading and installing it in
#'   '~/.rscala/sbt' if necessary?
#'
#' @return Returns a list of details of the Scala and Java binaries.
#' @references {David B. Dahl (2018). “Integration of R and Scala Using rscala.”
#'   Journal of Statistical Software, in editing. https://www.jstatsoft.org}
#' @export
#' @examples \donttest{
#'
#' scalaConfig()
#' }
scalaConfig <- function(verbose=TRUE, reconfig=FALSE, download=character(0), require.sbt=FALSE) {
  if ( inherits(verbose,"rscalaBridge") ) return(attr(verbose,"details")$config)
  if ( ( length(download) > 0 ) && ( download == TRUE ) ) download <- c("java","scala","sbt")
  if ( length(setdiff(download,c("java","scala","sbt"))) > 0 ) stop('Invalid element in "download" argument.')
  download.java <- "java" %in% download
  download.scala <- "scala" %in% download
  download.sbt <- "sbt" %in% download
  if ( Sys.getenv("RSCALA_RECONFIG") != "" ) reconfig <- Sys.getenv("RSCALA_RECONFIG")
  consent <- identical(reconfig,TRUE) || download.java || download.scala || download.sbt
  installPath <- path.expand(file.path("~",".rscala"))
  dependsPath <- if ( Sys.getenv("RSCALA_BUILDING") != "" ) file.path(getwd(),"inst","dependencies") else ""
  offerInstall <- function(msg) {
    if ( !identical(reconfig,"live") && interactive() ) {
      while ( TRUE ) {
        cat(msg,"\n")
        response <- toupper(trimws(readline(prompt="Would you like to install now? [Y/n] ")))
        if ( response == "N" ) return(FALSE)
        if ( response %in% c("Y","") ) return(TRUE)
      }
    } else FALSE
  }
  configPath  <- file.path(installPath,"config.R")
  if ( identical(reconfig,FALSE) && file.exists(configPath) && !download.java && !download.scala && !download.sbt ) {
    if ( verbose ) cat(paste0("\nRead existing configuration file: ",configPath,"\n\n"))
    source(configPath,chdir=TRUE,local=TRUE)
    if ( is.null(config$format) || ( config$format < 4L ) || ( ! all(file.exists(c(config$javaHome,config$scalaHome,config$javaCmd,config$scalaCmd))) ) || ( is.null(config$sbtCmd) && require.sbt ) || ( ! is.null(config$sbtCmd) && ! file.exists(config$sbtCmd) ) ) {
      if ( verbose ) cat("The 'config.R' is out-of-date.  Reconfiguring...\n")
      unlink(configPath)
      scalaConfig(verbose, reconfig, download, require.sbt)
    } else config
  } else {
    if ( download.java ) installJava(installPath,verbose)
    javaConf <- findExecutable("java","Java",installPath,javaSpecifics,verbose)
    if ( is.null(javaConf) ) {
      if ( verbose ) cat("\n")
      consent2 <- offerInstall(paste0("Java and Scala are not found.")) 
      stopMsg <- "\n\n<<<<<<<<<<\n<<<<<<<<<<\n<<<<<<<<<<\n\nJava is not found!  Please run 'rscala::scalaConfig(download=\"java\")'\n\n>>>>>>>>>>\n>>>>>>>>>>\n>>>>>>>>>>\n"
      if ( consent2 ) {
        installJava(installPath,verbose)
        javaConf <- findExecutable("java","Java",installPath,javaSpecifics,verbose)
        if ( is.null(javaConf) ) stop(stopMsg)
      } else {
        if ( dependsPath != "" ) {
          installJava(dependsPath,verbose)
          javaConf <- findExecutable("java","Java",dependsPath,javaSpecifics,verbose)
          if ( is.null(javaConf) ) stop(stopMsg)
        }
        else stop(stopMsg)
      }
      consent <- consent || consent2
    }
    if ( download.scala ) installScala(installPath,javaConf,verbose)
    scalaSpecifics2 <- function(x,y) scalaSpecifics(x,javaConf,y)
    scalaConf <- findExecutable("scala","Scala",installPath,scalaSpecifics2,verbose)
    if ( is.null(scalaConf) ) {
      if ( verbose ) cat("\n")
      consent2 <- consent || offerInstall(paste0("Scala is not found.")) 
      stopMsg <- "\n\n<<<<<<<<<<\n<<<<<<<<<<\n<<<<<<<<<<\n\nScala is not found!  Please run 'rscala::scalaConfig(download=\"scala\")'\n\n>>>>>>>>>>\n>>>>>>>>>>\n>>>>>>>>>>\n"
      if ( consent2 ) {
        installScala(installPath,javaConf,verbose)
        scalaConf <- findExecutable("scala","Scala",installPath,scalaSpecifics2,verbose)
        if ( is.null(scalaConf) ) stop(stopMsg)
      } else {
        if ( dependsPath != "" ) {
          installScala(dependsPath,javaConf,verbose)
          scalaConf <- findExecutable("scala","Scala",dependsPath,scalaSpecifics2,verbose)
          if ( is.null(scalaConf) ) stop(stopMsg)
        }
        else stop(stopMsg)
      }
      consent <- consent || consent2
    }
    osArchitecture <- if ( javaConf$javaArchitecture == 32 ) {
      osArchitecture <- if ( isOS64bit() ) 64 else 32
      if ( osArchitecture == 64 ) {
        warning("32-bit Java is paired with a 64-bit operating system.  To access more memory, please run 'scalaConfig(download=\"java\")'.")
      }
      osArchitecture
    } else javaConf$javaArchitecture
    config <- c(format=4L,osArchitecture=osArchitecture,scalaConf,javaConf)
    if ( download.sbt ) installSBT(installPath,config,verbose)
    sbtSpecifics <- function(x,y) list(sbtCmd=x)
    sbtConf <- findExecutable("sbt","SBT",installPath,sbtSpecifics,verbose)
    if ( is.null(sbtConf) && require.sbt ) {
      if ( verbose ) cat("\n")
      consent2 <- consent || offerInstall(paste0("SBT is not found.")) 
      stopMsg <- "\n\n<<<<<<<<<<\n<<<<<<<<<<\n<<<<<<<<<<\n\nSBT is not found!  Please run 'rscala::scalaConfig(download=\"sbt\")'\n\n>>>>>>>>>>\n>>>>>>>>>>\n>>>>>>>>>>\n"
      if ( consent2 ) {
        installSBT(installPath,config,verbose)
        sbtConf <- findExecutable("sbt","SBT",installPath,sbtSpecifics,verbose)
        if ( is.null(sbtConf) )  stop(stopMsg)
      } else stop(stopMsg)
      consent <- consent || consent2      
    }
    config <- c(config,sbtConf)
    if ( !consent && verbose ) cat("\n")
    writeConfig <- consent || offerInstall(paste0("File '",configPath,"' is not found or is out-of-date."))
    if ( writeConfig ) {
      dir.create(installPath,showWarnings=FALSE,recursive=TRUE)
      outFile <- file(configPath,open="w")
      dump("config",file=outFile)
      close(outFile)
      if ( verbose ) cat(paste0("\nWrote configuration file: ",configPath,"\n\n"))
    } else if ( verbose ) cat("\n")
    config
  }
}

findExecutable <- function(mode,prettyMode,installPath,mapper,verbose=TRUE) {  ## Mimic how the 'scala' script finds Java.
  tryCandidate <- function(candidate) {
    if ( ! is.null(candidate) && length(candidate) == 1 && candidate != "" && file.exists(candidate) ) {
      if ( verbose ) cat(paste0("  Success with ",label,".\n"))
      result <- mapper(candidate,verbose)
      if ( is.character(result) ) {
        if ( verbose ) cat(paste0("  ... but ",result,"\n"))
        NULL
      } else result
    } else {
      if ( verbose ) cat(paste0("  Failure with ",label,".\n"))
      NULL
    }
  }
  allCaps <- toupper(mode)
  if ( verbose ) cat(paste0("\nSearching the system for ",prettyMode,".\n"))
  ###
  label <- "directory"
  regex <- sprintf("%s%s$",mode,if ( .Platform$OS.type == "windows" ) "(\\.exe|\\.bat)" else "")
  candidates <- list.files(installPath,paste0("^",regex),recursive=TRUE)
  candidates <- candidates[grepl(sprintf("^%s/(.*/|)bin/%s",mode,regex),candidates)]
  if ( length(candidates) > 1 ) candidates <- candidates[which.min(nchar(candidates))]
  conf <- tryCandidate(file.path(installPath,candidates))
  if ( ! is.null(conf) ) return(conf)
  ###
  if ( mode == "java" ) {
    label <- paste0("R CMD config JAVA")
    path <- tryCatch(system2(file.path(R.home("bin"),"R"),c("CMD","config","JAVA"),stdout=TRUE,stderr=FALSE), warning=function(e) NULL, error=function(e) NULL)
    conf <- tryCandidate(path)
    if ( ! is.null(conf) ) return(conf)
  }
  ###
  label <- paste0(allCaps,"CMD environment variable")
  conf <- tryCandidate(Sys.getenv(paste0(allCaps,"CMD")))
  if ( ! is.null(conf) ) return(conf)
  ###
  label <- paste0(allCaps,"_HOME environment variable")
  home <- Sys.getenv(paste0(allCaps,"_HOME"))
  conf <- tryCandidate(if ( home != "" ) file.path(home,"bin",mode) else "")
  if ( ! is.null(conf) ) return(conf)
  ###
  label <- "PATH environment variable"
  conf <- tryCandidate(Sys.which(mode)[[mode]])
  if ( ! is.null(conf) ) return(conf)
  ###
  if ( Sys.getenv("RSCALA_BUILDING") == "" ) {
    label <- "package build directory"
    regex <- sprintf("%s%s$",mode,if ( .Platform$OS.type == "windows" ) "(\\.exe|\\.bat)" else "")
    dependsPath <- file.path(system.file(package="rscala"),"dependencies")
    candidates <- list.files(dependsPath,paste0("^",regex),recursive=TRUE)
    candidates <- candidates[grepl(sprintf("^%s/(.*/|)bin/%s",mode,regex),candidates)]
    if ( length(candidates) > 1 ) candidates <- candidates[which.min(nchar(candidates))]
    conf <- tryCandidate(file.path(dependsPath,candidates))
    if ( ! is.null(conf) ) return(conf)    
  }
  NULL
}

isOS64bit <- function() {
  if ( identical(.Platform$OS.type,"windows") ) {
    out <- system2("wmic",c("/locale:ms_409","OS","get","osarchitecture","/VALUE"),stdout=TRUE)
    any("OSArchitecture=64-bit"==trimws(out))
  } else identical(system2("uname","-m",stdout=TRUE),"x86_64")
}
      
getURL <- function(software, version, attempt=1, counter=1) {
  stub <- if ( counter == 1 )       sprintf("https://raw.githubusercontent.com/dbdahl/rscala")
          else if ( counter == 2 )  sprintf("https://dahl-git.byu.edu/dahl/rscala/raw")
          else return(NULL)
  url <- if ( software == "java" ) {
    os <- osType()
    if ( ! ( os %in% c("windows","mac","linux") ) ) stop(sprintf("Cannot automatically download Java for %s.",osType))
    if ( ! isOS64bit() ) stop(sprintf("Cannot automatically download Java for a 32-bit operating system.",osType))
    sprintf("%s/master/url/java/%s/%s/%s",stub,os,version,attempt)
  } else if ( software == "scala" ) {
    sprintf("%s/master/url/scala/%s/%s",stub,version,attempt)   
  } else if ( software == "sbt" ) {
    sprintf("%s/master/url/sbt/%s/%s",stub,version,attempt)   
  } else stop("Request for unsupported software.")
  url2 <- tryCatch(readLines(url),error=function(e) NULL,warning=function(e) NULL)
  if ( is.null(url2) && ( counter < 2 ) ) getURL(software, version, attempt, counter+1) else url2
}

installJava <- function(installPath, verbose, attempt=1) {
  if ( verbose ) cat("\nDownloading Java.\n")
  dir.create(installPath,showWarnings=FALSE,recursive=TRUE)
  version <- Sys.getenv("RSCALA_JAVA_MAJORVERSION","8")
  attempt <- as.integer(Sys.getenv("RSCALA_JAVA_ATTEMPT",attempt))
  url <- getURL("java",version,attempt)
  installPathTemp <- file.path(installPath,"tmp")
  unlink(installPathTemp,recursive=TRUE,force=TRUE)
  dir.create(installPathTemp,showWarnings=FALSE,recursive=TRUE)
  destfile <- tempfile("jdk",tmpdir=installPathTemp)
  result <- tryCatch(utils::download.file(url, destfile, mode="wb"), error=function(e) 1, warning=function(e) 1)
  if ( result != 0 ) {
    unlink(destfile,force=TRUE)
    msg <- "Failed to download installation."
    if ( attempt < 2 ) {
      if ( verbose ) cat(paste0(msg,"\n"))
      installJava(installPath,verbose,attempt+1)
      return(NULL)
    } else stop(msg)
  }
  if ( verbose ) cat("Extracting Java.\n")
  os <- osType()
  func <- if ( os == "windows" ) function(x) utils::unzip(x,exdir=installPathTemp,unzip="internal")
  else function(x) utils::untar(x,exdir=installPathTemp,tar="internal")
  func(destfile)
  unlink(destfile,force=TRUE)
  destdir <- file.path(installPath,"java")
  unlink(destdir,recursive=TRUE,force=TRUE)  # Delete older version
  javaHome <- list.files(installPathTemp,full.names=TRUE,recursive=FALSE)
  javaHome <- javaHome[dir.exists(javaHome)]
  if ( length(javaHome) != 1 ) stop(paste0("Problem extracting Java.  Delete the directory '",installPath,"' and try again."))
  file.rename(javaHome,destdir)
  unlink(installPathTemp,recursive=TRUE,force=TRUE)
  if ( verbose ) cat("Successfully installed Java at ",destdir,"\n",sep="")
  NULL
}

installScala <- function(installPath, javaConf, verbose, attempt=1) {
  if ( verbose ) cat("\nDownloading Scala.\n")
  dir.create(installPath,showWarnings=FALSE,recursive=TRUE)
  unlink(file.path(installPath,"scala"),recursive=TRUE)  # Delete older version
  majorVersion <- Sys.getenv("RSCALA_SCALA_MAJORVERSION","2.12")
  if ( javaConf$javaMajorVersion <= 7 ) majorVersion <- "2.11"
  attempt <- as.integer(Sys.getenv("RSCALA_SCALA_ATTEMPT",attempt))
  url <- getURL("scala",majorVersion,attempt)
  dir.create(installPath,showWarnings=FALSE,recursive=TRUE)
  destfile <- file.path(installPath,basename(url))
  result <- tryCatch(utils::download.file(url, destfile), error=function(e) 1, warning=function(e) 1)
  if ( result != 0 ) {
    unlink(destfile)
    msg <- "Failed to download installation."
    if ( attempt < 2 ) {
      if ( verbose ) cat(paste0(msg,"\n"))
      installScala(installPath,javaConf,verbose,attempt+1)
      return(NULL)
    } else stop(msg)
  }
  if ( verbose ) cat("Extracting Scala.\n")
  result <- utils::untar(destfile,exdir=installPath,tar="internal")    # Use internal to avoid problems on a Mac.
  unlink(destfile)
  if ( result == 0 ) {
    destdir <- file.path(installPath,"scala")
    scalaHome <- list.files(installPath,sprintf("^scala-%s",majorVersion),full.names=TRUE)
    if ( length(scalaHome) != 1 ) stop(paste0("Problem extracting Scala.  Delete the directory '",installPath,"' and try again."))
    file.rename(scalaHome,destdir)
    if ( verbose ) cat("Successfully installed Scala at ",destdir,"\n",sep="")   
  } else {
    stop("Failed to extract installation.")
  }
  NULL
}

installSBT <- function(installPath, javaConf, verbose, attempt=1) {
  if ( verbose ) cat("\nDownloading SBT.\n")
  version <- Sys.getenv("RSCALA_SBT_MAJORVERSION","1.2")
  dir.create(installPath,showWarnings=FALSE,recursive=TRUE)
  unlink(file.path(installPath,"sbt"),recursive=TRUE)  # Delete older version
  # if ( javaConf$javaMajorVersion != 8 ) stop("Java 8 is recommended for SBT.")
  attempt <- as.integer(Sys.getenv("RSCALA_SBT_ATTEMPT",attempt))
  url <- getURL("sbt",version,attempt)
  dir.create(installPath,showWarnings=FALSE,recursive=TRUE)
  destfile <- file.path(installPath,basename(url))
  result <- tryCatch(utils::download.file(url, destfile), error=function(e) 1, warning=function(e) 1)
  if ( result != 0 ) {
    unlink(destfile)
    msg <- "Failed to download installation."
    if ( attempt < 2 ) {
      if ( verbose ) cat(paste0(msg,"\n"))
      installSBT(installPath,javaConf,verbose,attempt+1)
      return(NULL)
    } else stop(msg)
  }
  if ( verbose ) cat("Extracting SBT.\n")
  result <- utils::untar(destfile,exdir=installPath,tar="internal")    # Use internal to avoid problems on a Mac.
  unlink(destfile)
  if ( result == 0 ) {
    destdir <- file.path(installPath,"sbt")
    if ( file.exists(destdir) ) if ( verbose ) cat("Successfully installed SBT at ",destdir,"\n",sep="")   
    else stop("Failed to extract installation.")
  } else {
    stop("Failed to extract installation.")
  }
  NULL
}

javaSpecifics <- function(javaCmd,verbose) {
  if ( verbose ) cat("  ... querying Java specifics.\n")
  response <- system2(javaCmd,"-version",stdout=TRUE,stderr=TRUE)
  # Get version information
  versionRegexp <- '(java|openjdk) version "([^"]*)".*'
  line <- response[grepl(versionRegexp,response)]
  if ( length(line) != 1 ) return(paste0("cannot determine Java version.  Output is:\n",paste(response,collapse="\n")))
  versionString <- gsub(versionRegexp,"\\2",line)
  versionParts <- strsplit(versionString,"(\\.|-)")[[1]]
  versionNumberString <- if ( versionParts[1] == '1' ) versionParts[2] else versionParts[1]
  versionNumber <- tryCatch(
    as.numeric(versionNumberString),
    warning=function(e) 0
  )
  if ( versionNumber < 8 ) return(paste0("unsupported Java version: ",versionString))
  # Determine if 32 or 64 bit
  bit <- if ( any(grepl('^(Java HotSpot|OpenJDK).* 64-Bit (Server|Client) VM.*$',response)) ||
              any(grepl('^IBM .* amd64-64 .*$',response)) ) 64 else 32
  list(javaCmd=javaCmd, javaMajorVersion=versionNumber, javaArchitecture=bit)
}

setJavaEnv <- function(javaConf) {
  oldJAVACMD <- Sys.getenv("JAVACMD",unset="--unset--")
  oldJAVAHOME <- Sys.getenv("JAVA_HOME",unset="--unset--")
  if ( oldJAVACMD  == "--unset--" ) oldJAVACMD  <- NULL
  if ( oldJAVAHOME == "--unset--" ) oldJAVAHOME <- NULL
  if ( is.null(javaConf$javaCmd)  ) Sys.unsetenv("JAVACMD")   else Sys.setenv(JAVACMD= javaConf$javaCmd)
  if ( is.null(javaConf$javaHome) ) Sys.unsetenv("JAVA_HOME") else Sys.setenv(JAVAHOME=javaConf$javaHome)
  list(javaCmd=oldJAVACMD,javaHome=oldJAVAHOME)
}

scalaMajorVersion <- function(scalaVersion) {
  if ( grepl(".*-.*",scalaVersion) ) scalaVersion
  else gsub("(^[23]\\.[0-9]+)\\..*","\\1",scalaVersion)
}

scalaSpecifics <- function(scalaCmd,javaConf,verbose) {
  if ( verbose ) cat("  ... querying Scala specifics.\n")
  oldJavaEnv <- setJavaEnv(javaConf)
  info <- tryCatch({
    system2(scalaCmd,c("-nobootcp","-nc","-e",shQuote('import util.Properties._; println(Seq(versionNumberString,scalaHome,javaHome).mkString(lineSeparator))')),stdout=TRUE,stderr=FALSE)
   }, warning=function(e) "")
  setJavaEnv(oldJavaEnv)
  fullVersion <- info[1]
  majorVersion <- scalaMajorVersion(fullVersion)
  if ( majorVersion == "" ) majorVersion <- "?"
  supportedVersions <- names(scalaVersionJARs())
  if ( ( length(supportedVersions) > 0 ) && ! ( majorVersion %in% supportedVersions ) ) paste0("unsupported Scala version: ",majorVersion)
  else {
    if ( ( majorVersion == "2.11" ) && ( javaConf$javaMajorVersion > 8 ) ) {
      sprintf("Scala %s is not supported on Java %s.",majorVersion,javaConf$javaMajorVersion)
    } else {
      list(scalaHome=info[2], scalaCmd=scalaCmd, scalaMajorVersion=majorVersion, scalaFullVersion=fullVersion, javaHome=info[3])
    }
  }
}
