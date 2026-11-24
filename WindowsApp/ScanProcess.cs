using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;
namespace SpaceSniffer.Windows {
 public sealed class ScanProcess:IDisposable {
  readonly Process process;readonly string workspace;bool disposed;int cancelRequested;
  public event Action<string> Progress;
  public ScanProcess(string root){
   workspace=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"SpaceSniffer","Runs",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(workspace);
   process=new Process{StartInfo=new ProcessStartInfo{FileName=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"WindowsScan.exe"),Arguments="--scan "+Quote(root)+" --output "+Quote(Path.Combine(workspace,"snapshot.json")),UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,RedirectStandardInput=true,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8}};
  }
  static string Quote(string s){return "\""+s.TrimEnd('\\').Replace("\"","\\\"")+(s.EndsWith("\\")?"\\\\":"")+"\"";}
  public Task<Snapshot> Run(){return Task.Run(()=>{
   try{
    process.Start();if(System.Threading.Volatile.Read(ref cancelRequested)!=0)Cancel();string errors="";process.ErrorDataReceived+=(s,e)=>{if(e.Data!=null&&errors.Length<8192)errors+=e.Data+"\n";};process.BeginErrorReadLine();
    string line;while((line=process.StandardOutput.ReadLine())!=null){var notify=Progress;if(notify!=null)notify(line);}
    process.WaitForExit();if(process.ExitCode!=0)throw new IOException("분석 엔진 오류 ("+process.ExitCode+")\n"+errors);
    return Snapshot.Load(Path.Combine(workspace,"snapshot.json"));
   }finally{try{Directory.Delete(workspace,true);}catch{}}
  });}
  public void Cancel(){System.Threading.Interlocked.Exchange(ref cancelRequested,1);try{if(!process.HasExited){process.StandardInput.WriteLine("cancel");process.StandardInput.Flush();}}catch(InvalidOperationException){}catch(IOException){} }
  public void Dispose(){if(disposed)return;disposed=true;Cancel();Task.Run(()=>{try{if(!process.WaitForExit(5000))process.Kill();}catch(InvalidOperationException){}finally{process.Dispose();}});}
 }
}
