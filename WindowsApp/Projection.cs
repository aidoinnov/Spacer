using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
namespace SpaceSniffer.Windows {
 public sealed class Projection {
  public Snapshot Source;public ulong[] Weights;public int[] Children;public int Focus;public bool Logical;
  public static Projection Build(Snapshot source,int focus,string expression,bool logical,bool hidden) {
   var predicate=new FilePredicate(expression);var weights=new ulong[source.nodes.Length];var visible=new bool[source.nodes.Length];
   for(int i=0;i<source.nodes.Length;i++){
    Node n=source.nodes[i];visible[i]=(i==0||visible[n.parent.Value])&&(hidden||(n.attributes&2)==0||i==0);
    if(visible[i]&&!n.directory&&predicate.Matches(n,logical))weights[i]=logical?n.logical:n.allocated;
   }
   for(int i=source.nodes.Length-1;i>0;i--)weights[source.nodes[i].parent.Value]=checked(weights[source.nodes[i].parent.Value]+weights[i]);
   int[] children=source.nodes[focus].children.Where(i=>visible[i]&&(weights[i]>0||String.IsNullOrWhiteSpace(expression))).OrderByDescending(i=>weights[i]).ThenBy(i=>source.nodes[i].name,StringComparer.OrdinalIgnoreCase).ToArray();
   return new Projection{Source=source,Weights=weights,Children=children,Focus=focus,Logical=logical};
  }
 }
 public sealed class FilePredicate {
  readonly List<Regex> include=new List<Regex>(),exclude=new List<Regex>();readonly List<string> paths=new List<string>();
  readonly List<Tuple<char,ulong>> sizes=new List<Tuple<char,ulong>>();
  public FilePredicate(string text){
   foreach(string raw in (text??"").Split(';')){
    string token=raw.Trim();if(token.Length==0)continue;
    if(token[0]=='>'||token[0]=='<'){
     Match m=Regex.Match(token,@"^([<>])\s*(\d+(?:\.\d+)?)\s*(b|kb|mb|gb|tb)?$",RegexOptions.IgnoreCase);
     if(!m.Success)throw new FormatException("크기 조건은 >100MB 또는 <1GB 형식으로 입력하세요.");
     double value=double.Parse(m.Groups[2].Value,CultureInfo.InvariantCulture);string unit=m.Groups[3].Value.ToLowerInvariant();int power=Array.IndexOf(new[]{"b","kb","mb","gb","tb"},unit);if(power<0)power=0;
     double bytes=value*Math.Pow(1000,power);if(bytes>ulong.MaxValue)throw new FormatException("크기가 너무 큽니다.");sizes.Add(Tuple.Create(token[0],(ulong)bytes));
    }else if(token[0]=='\\'){paths.Add(token.Trim('\\'));}
    else {bool negative=token[0]=='|';if(negative)token=token.Substring(1);if(token.Length==0)throw new FormatException("제외할 이름을 입력하세요.");
     string pattern="^"+Regex.Escape(token).Replace(@"\*",".*").Replace(@"\?",".")+"$";(negative?exclude:include).Add(new Regex(pattern,RegexOptions.IgnoreCase|RegexOptions.CultureInvariant));}
   }
  }
  public bool Matches(Node n,bool logical){
   ulong size=logical?n.logical:n.allocated;
   foreach(var s in sizes)if(s.Item1=='>'?size<=s.Item2:size>=s.Item2)return false;
   foreach(var path in paths)if(n.path.IndexOf("\\"+path+"\\",StringComparison.OrdinalIgnoreCase)<0)return false;
   if(exclude.Any(r=>r.IsMatch(n.name)))return false;return include.Count==0||include.Any(r=>r.IsMatch(n.name));
  }
 }
}
