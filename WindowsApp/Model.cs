using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Web.Script.Serialization;
namespace SpaceSniffer.Windows {
 public sealed class Node {
  public int id {get;set;} public int? parent {get;set;} public string name {get;set;} public string path {get;set;}
  public bool directory {get;set;} public ulong logical {get;set;} public ulong allocated {get;set;}
  public uint attributes {get;set;} public bool boundary {get;set;} public uint? error {get;set;} public int[] children {get;set;}
 }
 public sealed class Snapshot {
  public int schema {get;set;} public string root {get;set;} public bool cancelled {get;set;}
  public int files {get;set;} public int folders {get;set;} public int errors {get;set;} public int excluded {get;set;}
  public double elapsedSeconds {get;set;} public Node[] nodes {get;set;}
  public static JavaScriptSerializer Serializer(){return new JavaScriptSerializer{MaxJsonLength=int.MaxValue,RecursionLimit=256};}
  public static Snapshot Load(string path) {
   var s=Serializer().Deserialize<Snapshot>(File.ReadAllText(path));
   if(s==null||s.schema!=1||s.nodes==null||s.nodes.Length==0||s.nodes[0].parent!=null)throw new InvalidDataException("지원하지 않거나 잘못된 스냅샷입니다.");
   int files=0,folders=0,errors=0,excluded=0;var references=new int[s.nodes.Length];var logical=new ulong[s.nodes.Length];var allocated=new ulong[s.nodes.Length];
   for(int i=0;i<s.nodes.Length;i++){
    var n=s.nodes[i];if(n.id!=i||n.children==null||n.name==null||n.path==null||i>0&&(!n.parent.HasValue||n.parent.Value<0||n.parent.Value>=i))throw new InvalidDataException("노드 구조가 올바르지 않습니다.");
    foreach(int child in n.children){if(child<=i||child>=s.nodes.Length||s.nodes[child].parent!=i||++references[child]!=1)throw new InvalidDataException("하위 항목 연결이 올바르지 않습니다.");}
    if(n.error.HasValue)errors++;if(n.boundary)excluded++;if(!n.directory){logical[i]=n.logical;allocated[i]=n.allocated;}
    if(n.directory)folders++;else files++;
   }
   if(files!=s.files||folders!=s.folders||errors!=s.errors||excluded!=s.excluded)throw new InvalidDataException("파일 수 또는 오류 수가 일치하지 않습니다.");
   for(int i=s.nodes.Length-1;i>0;i--){if(references[i]!=1)throw new InvalidDataException("연결되지 않은 항목입니다.");int parent=s.nodes[i].parent.Value;logical[parent]=checked(logical[parent]+logical[i]);allocated[parent]=checked(allocated[parent]+allocated[i]);}
   for(int i=0;i<s.nodes.Length;i++)if(s.nodes[i].logical!=logical[i]||s.nodes[i].allocated!=allocated[i])throw new InvalidDataException("용량 합계가 일치하지 않습니다.");return s;
  }
 }
 public static class Display {
  public static string Bytes(ulong b){string[] units={"B","KB","MB","GB","TB","PB"};double v=b;int i=0;while(v>=1000&&i<units.Length-1){v/=1000;i++;}return v.ToString(i==0?"N0":"N1",CultureInfo.CurrentCulture)+" "+units[i];}
 }
}
