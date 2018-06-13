package org.ddahl.rscala2.server

import Protocol._
import scala.tools.nsc.interpreter.{ILoop, IMain}
import scala.tools.nsc.interpreter.IR.Success
import scala.tools.nsc.Settings
import scala.annotation.tailrec
import scala.collection.mutable.HashMap
import java.net._
import java.io._
import java.nio.ByteBuffer

object Server extends App {

  val serializeOutput = false
  val debug = false
  val technique: Either[(Int, Int), (String, String)] = Left(9998, 9999)
  //val technique: Either[(Int,Int),(String,String)] = Right("/home/dahl/docs/devel/rscala2/R/rscala2/pipe-s2r","/home/dahl/docs/devel/rscala2/R/rscala2/pipe-r2s")
  val buffer = false

  // Set classpath
  private val settings = new Settings()
  settings.embeddedDefaults[Datum]
//  val initialClasspath = (java.lang.Thread.currentThread.getContextClassLoader match {
//    case cl: java.net.URLClassLoader => cl.getURLs.toList
//    case e => sys.error("Classloader is not a URLClassLoader: "+e)
//  }).map(_.getPath)
//  settings.classpath.value = initialClasspath.distinct.mkString(java.io.File.pathSeparator)
  settings.deprecation.value = true
  settings.feature.value = true
  settings.unchecked.value = true
  settings.language.add("reflectiveCalls")

  // Set up sinks
  val (debugger, prntWrtr, baosOut, baosErr) = serializeOutput match {
    case true =>
      val out = new ByteArrayOutputStream()
      val err = new ByteArrayOutputStream()
      val pw = new PrintWriter(out)
      val d = new Debugger(debug, pw, "Scala", false)
      (d, pw, out, err)
    case false =>
      val pw = new PrintWriter(System.out, true)
      val d = new Debugger(debug, pw, "Scala", false)
      (d, pw, null, null)
  }
//  if (debugger.on) debugger("Initial classpath is:\n" + initialClasspath.mkString("\n"))

  // Instantiate an interpreter
  val intp = new IMain(settings, prntWrtr)
  // Don't be chatty
  locally {
    val iloop = new ILoop()
    iloop.intp = intp
    iloop.verbosity()
  }

  debugger("starting server")

  private val (out, in) = {
    val buffer = false
    val (os,is) = if ( technique.isLeft ) {
      val (portS2R, portR2S) = technique.left.get
      val serverOut = new ServerSocket(portS2R)
      val serverIn = new ServerSocket(portR2S)
      if ( debugger.on) debugger("socket S2R waiting for client on port: "+portS2R)
      val sOut = serverOut.accept()
      if ( debugger.on ) debugger("socket R2S waiting for client on port: "+portR2S)
      val sIn = serverIn.accept()
      (sOut.getOutputStream, sIn.getInputStream)
    } else {
      val (pipeS2R, pipeR2S) = technique.right.get
      if ( debugger.on ) debugger("pipe S2R client is: "+pipeS2R)
      if ( debugger.on ) debugger("pipe R2S client is: "+pipeR2S)
      val fos = new FileOutputStream(pipeS2R)
      val fis = new FileInputStream(pipeR2S)
      (fos, fis)
    }
    val bos = if ( buffer ) new BufferedOutputStream(os) else os
    (new DataOutputStream(bos), new DataInputStream(is))
  }
  if ( debugger.on ) debugger("connections established")

  private val embeddedStack = new EmbeddedStack()    // called ES in the REPL
  intp.bind("ES",embeddedStack)
  private val functionMap = new HashMap[String, (Any,String)]()
  private val unary = Class.forName("scala.Function0").getMethod("apply")
  unary.setAccessible(true)
  private val referenceMap = new HashMap[Int, (Any,String)]()

  def exit(): Unit = {
    if ( debugger.on ) debugger("exit")
    out.close()
    in.close()
  }

  private def readString(): String = {
    val nBytes = in.readInt()
    val bytes = new Array[Byte](nBytes)
    in.readFully(bytes)
    new String(bytes,"UTF-8")
  }

  private def writeString(x: String): Unit = {
    val bytes = x.getBytes("UTF-8")
    out.writeInt(bytes.length)
    out.write(bytes)
  }

  def push(): Unit = {
    if ( debugger.on ) debugger("push")
    val tipe = in.readByte()
    val value = tipe match {
      case TCODE_INT_0 =>
        in.readInt()
      case TCODE_INT_1 =>
        val len = in.readInt()
        val bytes = new Array[Byte](len*BYTES_PER_INT)
        in.readFully(bytes)
        val byteBuffer = ByteBuffer.wrap(bytes)
        Array.fill[Int](len) { byteBuffer.getInt() }
      case TCODE_DOUBLE_0 =>
        in.readDouble()
      case TCODE_DOUBLE_1 =>
        val len = in.readInt()
        val bytes = new Array[Byte](len*BYTES_PER_DOUBLE)
        in.readFully(bytes)
        val byteBuffer = ByteBuffer.wrap(bytes)
        Array.fill[Double](len) { byteBuffer.getDouble() }
      case TCODE_CHARACTER_0 =>
        readString()
      case _ =>
        throw new IllegalStateException("Unsupported type.")
    }
    embeddedStack.pushValue(Datum(value,tipe))
  }

  def report(datum: Datum): Unit = {
    if ( debugger.on ) debugger("report")
    embeddedStack.reset()
    val tipe = datum.tipe
    out.writeByte(tipe)
    tipe match {
      case TCODE_INT_0 =>
        out.writeInt(datum.value.asInstanceOf[Int])
      case TCODE_INT_1 =>
        val value = datum.value.asInstanceOf[Array[Int]]
        val byteBuffer = ByteBuffer.allocate(value.length*BYTES_PER_INT)
        value.foreach(byteBuffer.putInt(_))
        out.writeInt(value.length)
        out.write(byteBuffer.array)
      case TCODE_DOUBLE_0 =>
        out.writeDouble(datum.value.asInstanceOf[Double])
      case TCODE_DOUBLE_1 =>
        val value = datum.value.asInstanceOf[Array[Double]]
        val byteBuffer = ByteBuffer.allocate(value.length*BYTES_PER_DOUBLE)
        value.foreach(byteBuffer.putDouble(_))
        out.writeInt(value.length)
        out.write(byteBuffer.array)
      case TCODE_CHARACTER_0 =>
        writeString(datum.value.asInstanceOf[String])
      case TCODE_UNIT =>
      case TCODE_REFERENCE =>
        val value = datum.value.asInstanceOf[(Any,String)]
        val key = {
          var candidate = scala.util.Random.nextInt()
          while ( referenceMap.contains(candidate) ) {
            candidate = scala.util.Random.nextInt()
          }
          candidate
        }
        referenceMap(key) = value
        out.writeInt(key)
        writeString(value._2)
      case TCODE_ERROR_DEF =>
        writeString(datum.value.asInstanceOf[String])
      case TCODE_ERROR_INVOKE =>
      case e =>
        throw new IllegalStateException("Unsupported type: "+e)
    }
    out.flush()
  }

  def invoke(withNames: Boolean): Unit = {
    if ( debugger.on ) debugger("invoke with" + (if (withNames) "" else "out") +" names")
    if ( withNames ) List.fill(embeddedStack.size)(readString()).foreach(embeddedStack.pushName)
    val snippet = readString()
    val sb = new java.lang.StringBuilder()
    sb.append("() => {\n")
    sb.append(embeddedStack)
    sb.append(snippet)
    if ( ! withNames ) sb.append(embeddedStack.argsList)
    sb.append("\n}")
    val body = sb.toString
    val (jvmFunction, resultType) = functionMap.getOrElse(body, {
      val result = intp.interpret(body)
      if ( result != Success ) {
        if ( debugger.on ) debugger("error in defining function.")
        report(Datum(body,TCODE_ERROR_DEF))
        return
      }
      val functionName = intp.mostRecentVar
      val jvmFunction = intp.valueOfTerm(functionName).get
      val resultType = {
        val r = intp.symbolOfLine(functionName).info.toString.substring(6)  // Drop "() => " in the return type.
        if ( r.startsWith("iw$") ) r.substring(3)
        else r
      }
      if ( debugger.on ) debugger("result type: "+resultType)
      val tuple = (jvmFunction, resultType)
      functionMap(body) = tuple
      if ( debugger.on ) debugger("function definition is okay.")
      tuple
    })
    val result = try {
      unary.invoke(jvmFunction)
    } catch {
      case e: Throwable =>
        report(Datum(e,TCODE_ERROR_INVOKE))
        return
    }
    if ( debugger.on ) debugger("function invocation is okay.")
    if ( typeMapper2.contains(resultType) ) {
      report(Datum(result, typeMapper2.get(resultType).get))
    } else {
      report(Datum((result, resultType), TCODE_REFERENCE))
    }
  }

  def echo(): Unit = {
    val value = in.readInt()
    report(Datum(value,TCODE_INT_0))
  }

  def gc(): Unit = {
    if ( debugger.on ) debugger("garbage collect")
    (0 until in.readInt()).foreach { i =>
      val key = in.readInt()
      referenceMap.remove(key)
    }
  }

  @tailrec
  def loop(): Unit = {
    if ( debugger.on ) debugger("main")
    val request = in.readByte()
    request match {
      case PCODE_EXIT => exit(); return
      case PCODE_PUSH => push()
      case PCODE_INVOKE_WITH_NAMES => invoke(true)
      case PCODE_INVOKE_WITHOUT_NAMES => invoke(false)
      case PCODE_ECHO => echo()
      case PCODE_GARBAGE_COLLECT => gc()
      case _ =>
        throw new IllegalStateException("Unsupported command: "+request)
    }
    loop()
  }

  loop()

}

