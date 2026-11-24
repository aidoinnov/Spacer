using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;
namespace SpaceSniffer.Windows {
 public sealed partial class MainWindow {
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool CreateHardLink(string newName,string existing,IntPtr reserved);
  [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr handle);
  [DllImport("kernel32.dll")]static extern uint GetProcessHandleCount(IntPtr process,out uint count);
  readonly List<string> checks=new List<string>();string selfTestOutput;
  async Task WaitFor(Func<bool> condition,string description,int timeout=60000){var clock=Stopwatch.StartNew();while(!condition()){if(clock.ElapsedMilliseconds>timeout)throw new Exception("Timeout: "+description+" · "+Status.Text);await Task.Delay(40);}}
  void Check(bool condition,string description){if(!condition)throw new Exception(description);checks.Add(description);SaveTestState("running",null);}
  void SaveTestState(string state,string error){if(selfTestOutput==null)return;try{var report=new{status=state,error=error,checks=checks.ToArray(),pid=Process.GetCurrentProcess().Id,session=Process.GetCurrentProcess().SessionId,window_visible=IsWindowVisible(Handle),window_handle=Handle.ToInt64(),window_title=Text,scan_active=IsScanning,projecting=IsProjecting,files=snapshot==null?0:snapshot.files,folders=snapshot==null?0:snapshot.folders,logical=snapshot==null?0:snapshot.nodes[0].logical,allocated=snapshot==null?0:snapshot.nodes[0].allocated,tiles=Map.TileCount,status_text=Status.Text};File.WriteAllText(Path.Combine(selfTestOutput,"ui-result.json"),Snapshot.Serializer().Serialize(report));}catch{} }
  void CaptureFrame(string name){using(var image=new Bitmap(ClientSize.Width,ClientSize.Height)){DrawToBitmap(image,new Rectangle(Point.Empty,ClientSize));image.Save(Path.Combine(selfTestOutput,name+".png"),System.Drawing.Imaging.ImageFormat.Png);}}
  internal async void RunSelfTest(string output){selfTestOutput=output;Directory.CreateDirectory(output);Watch.Checked=false;SaveTestState("preparing",null);string fixture=Path.Combine(output,"fixture");string empty=Path.Combine(output,"empty");Directory.CreateDirectory(empty);int count=0;ulong logical=0;
   try{
    Check(Visible&&IsWindowVisible(Handle)&&Process.GetCurrentProcess().SessionId!=0,"Native app window visible in interactive desktop");
    await Task.Run(()=>{
     Directory.CreateDirectory(fixture);
     for(int branch=0;branch<64;branch++){string folder=Path.Combine(fixture,"branch-"+branch.ToString("D3"));Directory.CreateDirectory(folder);for(int i=0;i<96;i++){int length=1024+i;File.WriteAllBytes(Path.Combine(folder,"f"+i.ToString("D3")+(i%4==0?".txt":".bin")),new byte[length]);count++;logical+=(ulong)length;}}
     string unicode=Path.Combine(fixture,"한글 空白");Directory.CreateDirectory(unicode);foreach(string n in new[]{"café.txt","cafe\u0301.txt","한글 이름.txt","🙂.txt"}){File.WriteAllBytes(Path.Combine(unicode,n),new byte[1024]);count++;logical+=1024;}
     string physical=Path.Combine(fixture,"physical.bin");File.WriteAllBytes(physical,new byte[10000]);count++;logical+=10000;
     if(!CreateHardLink(Path.Combine(fixture,"hardlink.bin"),physical,IntPtr.Zero))throw new Exception("CreateHardLink failed "+Marshal.GetLastWin32Error());count++;logical+=10000;
    });
    PathBox.Text=fixture;ScanButton.PerformClick();await WaitFor(()=>!IsScanning&&!IsProjecting&&snapshot!=null,"initial scan");
    Check(snapshot.files==count&&snapshot.nodes[0].logical==logical&&snapshot.errors==0,"Exact real file count and logical bytes");
    var links=snapshot.nodes.Where(n=>n.name=="physical.bin"||n.name=="hardlink.bin").ToArray();Check(links.Length==2&&links.Sum(n=>(decimal)n.allocated)>0&&links.Count(n=>n.allocated==0)==1,"Hard links count allocation once with native file identity");
    Check(snapshot.nodes.Any(n=>n.name=="café.txt")&&snapshot.nodes.Count(n=>n.name=="café.txt"||n.name=="cafe\u0301.txt")==2,"Unicode filenames survive native UTF16 scan");
    Check(Map.TileCount>0&&Listing.VirtualListSize>0,"Treemap and detail list populated");CaptureFrame("01-initial");
    int branchId=Array.FindIndex(snapshot.nodes,n=>n.name=="branch-000");Navigate(branchId,true);await WaitFor(()=>!IsProjecting,"folder navigation");Check(focus==branchId&&Listing.VirtualListSize==96,"Folder navigation uses real child list");UpButton.PerformClick();await WaitFor(()=>!IsProjecting,"up navigation");Check(focus==0,"Up returns to root");
    FilterBox.Text="*.txt;>1KB";RefreshProjection();await WaitFor(()=>!IsProjecting,"filter");Check(projection.Weights[0]>0&&projection.Weights[0]<snapshot.nodes[0].allocated&&FilterError.Text=="","Name and size filter updates visible weights");CaptureFrame("02-filter");
    FilterBox.Text=">invalid";RefreshProjection();await WaitFor(()=>!IsProjecting,"invalid filter");Check(FilterError.Text.Length>0&&snapshot.files==count,"Invalid filter reports an error without losing data");FilterBox.Text="*.txt;>1KB";RefreshProjection();await WaitFor(()=>!IsProjecting,"restore filter");
    string export=Path.Combine(output,"export.txt");ExportTo(export);Check(File.Exists(export)&&File.ReadAllText(export).Contains(".txt")&&!File.ReadAllText(export).Contains("physical.bin"),"TXT export respects current filter");
    FilterBox.Text="";RefreshProjection();await WaitFor(()=>!IsProjecting,"clear filter");Logical.Checked=true;await WaitFor(()=>!IsProjecting,"logical mode");Check(projection.Weights[0]==logical,"Logical size mode matches exact byte oracle");Logical.Checked=false;await WaitFor(()=>!IsProjecting,"allocated mode");
    string saved=Path.Combine(output,"snapshot.json");SaveTo(saved);Check(Snapshot.Load(saved).files==count,"Snapshot saves and independently reloads");
    OpenSnapshot(saved);await WaitFor(()=>offline&&!IsProjecting,"offline snapshot");Check(!RescanButton.Enabled,"Offline snapshot disables live rescan");
    PathBox.Text=fixture;ScanButton.PerformClick();await WaitFor(()=>!IsScanning&&!IsProjecting&&!offline,"resume live scan");
    Watch.Checked=true;string delta=Path.Combine(fixture,"watch-added.bin"),renamed=Path.Combine(fixture,"watch-renamed.bin");File.WriteAllBytes(delta,new byte[1234]);File.Move(delta,renamed);
    await WaitFor(()=>!IsScanning&&!IsProjecting&&snapshot.files==count+1&&snapshot.nodes.Any(n=>n.path==renamed),"native watcher create/rename");Check(snapshot.nodes[0].logical==logical+1234,"Live watcher converges after write and rename");File.Delete(renamed);await WaitFor(()=>!IsScanning&&!IsProjecting&&snapshot.files==count,"watch delete");Check(snapshot.nodes[0].logical==logical,"Live watcher removes deleted files");Watch.Checked=false;
    var baseline=snapshot;RescanButton.PerformClick();await WaitFor(()=>IsScanning,"rescan start");CancelButtonUI.PerformClick();await WaitFor(()=>!IsScanning&&!IsProjecting,"cancel/drain");Check(snapshot.files==count,"Cancel settles and preserves completed root");
    PathBox.Text=empty;ScanButton.PerformClick();await WaitFor(()=>!IsScanning&&!IsProjecting&&snapshot!=null&&snapshot.root==empty,"empty replacement");Check(snapshot.files==0&&snapshot.nodes.Length==1&&Map.TileCount==0,"Empty root replacement clears prior content");
    PathBox.Text=fixture;ScanButton.PerformClick();await WaitFor(()=>!IsScanning&&!IsProjecting&&snapshot.files==count,"final live scan");CaptureFrame("03-final");
    uint handles;GetProcessHandleCount(Process.GetCurrentProcess().Handle,out handles);File.WriteAllText(Path.Combine(output,"resources.json"),Snapshot.Serializer().Serialize(new{handles=handles,working_set=Process.GetCurrentProcess().WorkingSet64,scan_active=IsScanning}));
    SaveTestState("passed",null);
   }catch(Exception ex){SaveTestState("failed",ex.ToString());CaptureFrame("failure");}
  }
 }
}
