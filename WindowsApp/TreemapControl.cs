using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
namespace SpaceSniffer.Windows {
 public sealed class TreemapControl:Control {
  public sealed class Tile{public int Id;public string Name;public ulong Weight;public RectangleF Rect;}
  readonly List<Tile> tiles=new List<Tile>();Projection projection;readonly ToolTip tip=new ToolTip();int hovered=-1,selected=-1;
  public event Action<int> Activated;public event Action<int> Picked;
  public int TileCount{get{return tiles.Count;}}
  public TreemapControl(){DoubleBuffered=true;BackColor=Color.FromArgb(14,20,25);SetStyle(ControlStyles.ResizeRedraw,true);}
  public void Clear(){projection=null;tiles.Clear();selected=-1;tip.SetToolTip(this,"");Invalidate();}
  public void ShowProjection(Projection p){projection=p;Rebuild();}
  public void SelectNode(int id){selected=id;Invalidate();}
  protected override void OnResize(EventArgs e){base.OnResize(e);Rebuild();}
  void Rebuild(){tiles.Clear();hovered=-1;tip.SetToolTip(this,"");if(projection!=null){
   var ids=projection.Children.Where(i=>projection.Weights[i]>0).ToArray();
   foreach(int id in ids.Take(2000))tiles.Add(new Tile{Id=id,Name=projection.Source.nodes[id].name,Weight=projection.Weights[id]});
   if(ids.Length>2000){ulong rest=0;foreach(int id in ids.Skip(2000))rest+=projection.Weights[id];tiles.Add(new Tile{Id=-1,Name="기타 "+(ids.Length-2000).ToString("N0")+"개 (목록에서 탐색)",Weight=rest});}
   LayoutTiles(0,tiles.Count,new RectangleF(5,5,Math.Max(0,ClientSize.Width-10),Math.Max(0,ClientSize.Height-10)));
  }Invalidate();}
  void LayoutTiles(int start,int count,RectangleF box){if(count<=0)return;if(count==1){tiles[start].Rect=box;return;}
   double total=0;for(int i=start;i<start+count;i++)total+=tiles[i].Weight;
   if(total<=0)return;double first=0;int cut=start;while(cut<start+count-1&&(first<total/2||cut==start)){first+=tiles[cut].Weight;cut++;}
   float fraction=(float)(first/total);RectangleF a=box,b=box;
   if(box.Width>=box.Height){a.Width=box.Width*fraction;b.X+=a.Width;b.Width-=a.Width;}else{a.Height=box.Height*fraction;b.Y+=a.Height;b.Height-=a.Height;}
   LayoutTiles(start,cut-start,a);LayoutTiles(cut,start+count-cut,b);
  }
  protected override void OnPaint(PaintEventArgs e){base.OnPaint(e);var g=e.Graphics;
   if(tiles.Count==0){TextRenderer.DrawText(g,projection==null?"폴더를 선택하고 분석을 시작하세요.":"이 조건에 표시할 항목이 없습니다.",Font,ClientRectangle,Color.Silver,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter);return;}
   foreach(var t in tiles){RectangleF r=t.Rect;r.Inflate(-1.5f,-1.5f);if(r.Width<1||r.Height<1)continue;
    bool folder=t.Id>=0&&projection.Source.nodes[t.Id].directory;int hash=t.Name.GetHashCode()&0x7fffffff;Color fill=folder?Color.FromArgb(27,57+hash%20,70+hash%20):Color.FromArgb(54+hash%28,65+hash%28,74+hash%30);
    using(var brush=new SolidBrush(fill))g.FillRectangle(brush,r);using(var pen=new Pen(t.Id==selected?Color.White:Color.FromArgb(72,110,125),t.Id==selected?2:1))g.DrawRectangle(pen,r.X,r.Y,r.Width,r.Height);
    if(r.Width>38&&r.Height>20){var label=Rectangle.Round(r);label.Inflate(-6,-4);label.Height=Math.Min(22,label.Height);TextRenderer.DrawText(g,(folder?"▸ ":"")+t.Name,Font,label,Color.Gainsboro,TextFormatFlags.EndEllipsis|TextFormatFlags.SingleLine);
     if(r.Height>46){label.Y+=24;TextRenderer.DrawText(g,Display.Bytes(t.Weight),Font,label,Color.Silver,TextFormatFlags.SingleLine|TextFormatFlags.EndEllipsis);}}
   }
  }
  int Hit(Point p){foreach(var t in tiles)if(t.Id>=0&&t.Rect.Contains(p))return t.Id;return -1;}
  protected override void OnMouseMove(MouseEventArgs e){base.OnMouseMove(e);int id=Hit(e.Location);if(id!=hovered){hovered=id;tip.SetToolTip(this,id<0?"":projection.Source.nodes[id].path+"\n"+Display.Bytes(projection.Weights[id]));}}
  protected override void OnMouseDown(MouseEventArgs e){base.OnMouseDown(e);int id=Hit(e.Location);selected=id;if(id>=0&&Picked!=null)Picked(id);Invalidate();}
  protected override void OnMouseDoubleClick(MouseEventArgs e){base.OnMouseDoubleClick(e);int id=Hit(e.Location);if(id>=0&&Activated!=null)Activated(id);}
  protected override void Dispose(bool disposing){if(disposing)tip.Dispose();base.Dispose(disposing);}
 }
}
