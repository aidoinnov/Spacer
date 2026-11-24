using System;
using System.IO;
using System.Text;
namespace SpaceSniffer.Windows {
 internal static class AtomicFile {
  public static void Write(string destination,Action<StreamWriter> body){
   string path=Path.GetFullPath(destination),temporary=Path.Combine(Path.GetDirectoryName(path),".sniffer-"+Guid.NewGuid().ToString("N")+".tmp");
   try{using(var stream=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None,65536,FileOptions.WriteThrough))using(var writer=new StreamWriter(stream,new UTF8Encoding(false))){body(writer);writer.Flush();stream.Flush(true);}if(File.Exists(path))File.Replace(temporary,path,null);else File.Move(temporary,path);}
   finally{if(File.Exists(temporary))File.Delete(temporary);}
  }
 }
}
