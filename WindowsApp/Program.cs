using System;
using System.Windows.Forms;
namespace SpaceSniffer.Windows {
 static class Program {
  [STAThread]static void Main(string[] args){Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new MainWindow(args));}
 }
}
