using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
namespace SpaceSniffer.Launcher {
 static class Program {
  static string Quote(string value){return "\""+value.TrimEnd('\\').Replace("\"","\\\"")+(value.EndsWith("\\")?"\\\\":"")+"\"";}
  [STAThread]static void Main(string[] args){
   string directory=AppDomain.CurrentDomain.BaseDirectory;
   var info=new ProcessStartInfo{FileName=Path.Combine(directory,"SpaceSniffer.exe"),WorkingDirectory=directory,UseShellExecute=false,Arguments=String.Join(" ",args.Select(Quote))};
   string windows=Environment.GetFolderPath(Environment.SpecialFolder.Windows);
   // The portable bundle must not accidentally depend on a developer's PATH.
   info.EnvironmentVariables["PATH"]=Path.Combine(windows,"System32")+";"+windows;
   try{using(var process=Process.Start(info)){process.WaitForExit();Environment.ExitCode=process.ExitCode;}}
   catch(Exception ex){System.Windows.Forms.MessageBox.Show(ex.Message,"Space Sniffer 실행 실패");Environment.ExitCode=1;}
  }
 }
}
