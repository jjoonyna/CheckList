package com.checklist.integration;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.time.Duration;
import java.util.concurrent.TimeUnit;
final class TestRedis implements AutoCloseable {
 final Process process;final int port;
 private TestRedis(Process process,int port){this.process=process;this.port=port;}
 static TestRedis start() throws Exception {
  String fallback=System.getProperty("os.name").toLowerCase().contains("windows")?Path.of(System.getProperty("user.home"),"AppData","Local","CheckListRuntime","redis-8.10.2","redis-server.exe").toString():"redis-server";
  String executable=System.getProperty("test.redis.executable",fallback);
  int port;try(ServerSocket free=new ServerSocket(0,0,InetAddress.getLoopbackAddress())){port=free.getLocalPort();}
  Path directory=Files.createTempDirectory("checklist-test-redis-");
  Files.writeString(directory.resolve("redis.conf"),"bind 127.0.0.1\nprotected-mode yes\nport "+port+"\nsave \"\"\nappendonly no\n",StandardCharsets.UTF_8);
  Process process=new ProcessBuilder(executable,"redis.conf").directory(directory.toFile()).redirectErrorStream(true).redirectOutput(directory.resolve("redis.log").toFile()).start();
  TestRedis redis=new TestRedis(process,port);
  long deadline=System.nanoTime()+Duration.ofSeconds(8).toNanos();
  while(System.nanoTime()<deadline){try(Socket socket=new Socket("127.0.0.1",port)){socket.setSoTimeout(1000);socket.getOutputStream().write("PING\r\n".getBytes(StandardCharsets.UTF_8));var reader=new BufferedReader(new InputStreamReader(socket.getInputStream(),StandardCharsets.UTF_8));if("+PONG".equals(reader.readLine()))return redis;}catch(IOException notReady){Thread.sleep(40);}}
  redis.close();throw new IllegalStateException("테스트 Redis 시작 실패: "+directory.resolve("redis.log"));
 }
 @Override public void close() throws Exception {
  try(Socket socket=new Socket("127.0.0.1",port)){socket.getOutputStream().write("SHUTDOWN NOSAVE\r\n".getBytes(StandardCharsets.UTF_8));}catch(IOException stopped){}
  if(!process.waitFor(5,TimeUnit.SECONDS))process.destroy();
 }
}