using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace TF3MP.UI {
    public sealed class ProgressMeter : Control {
        private int value;
        public ProgressBarStyle Style { get; set; }
        public int Value { get { return value; } set { this.value=Math.Max(0,Math.Min(100,value));Invalidate(); } }
        public ProgressMeter() { SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true); }
        protected override void OnPaint(PaintEventArgs e) {
            e.Graphics.Clear(Color.FromArgb(43,58,75));
            if(value>0)using(Brush brush=new SolidBrush(Color.FromArgb(96,205,255)))e.Graphics.FillRectangle(brush,0,0,Width*value/100,Height);
        }
    }
    public sealed class FriendList : ListBox {
        public int EditAreaWidth { get { return Math.Max(56,(int)(Font.Size*4)); } }
        public FriendList() { DrawMode=DrawMode.OwnerDrawFixed;ItemHeight=58;IntegralHeight=false; }
        protected override void OnDrawItem(DrawItemEventArgs e) {
            if(e.Index<0 || e.Index>=Items.Count)return;
            bool selected=(e.State&DrawItemState.Selected)!=0;
            using(Brush fill=new SolidBrush(selected ? Color.FromArgb(37,58,77) : BackColor))e.Graphics.FillRectangle(fill,e.Bounds);
            string name=GetItemText(Items[e.Index]);
            int size=Math.Min(e.Bounds.Height-12,38), x=e.Bounds.Left+14,y=e.Bounds.Top+(e.Bounds.Height-size)/2;
            e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            using(Brush avatar=new SolidBrush(Color.FromArgb(35,64,82)))e.Graphics.FillEllipse(avatar,x,y,size,size);
            string initial=name.Length==0 ? "?" : System.Globalization.StringInfo.GetNextTextElement(name).ToUpperInvariant();
            TextRenderer.DrawText(e.Graphics,initial,Font,new Rectangle(x,y,size,size),Color.FromArgb(96,205,255),TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter);
            Rectangle caption=new Rectangle(x+size+14,e.Bounds.Top,Math.Max(1,e.Bounds.Width-size-44-EditAreaWidth),e.Bounds.Height);
            TextRenderer.DrawText(e.Graphics,name,Font,caption,ForeColor,TextFormatFlags.Left|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis|TextFormatFlags.NoPrefix);
            Rectangle edit=new Rectangle(e.Bounds.Right-EditAreaWidth,e.Bounds.Top,EditAreaWidth,e.Bounds.Height);
            TextRenderer.DrawText(e.Graphics,"…",Font,edit,ForeColor,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter);
            if((e.State&DrawItemState.Focus)!=0)e.DrawFocusRectangle();
        }
    }
    // Paint the entire button once. Painting over the native disabled caption
    // caused overlapping text and looked like broken rendering in v66.
    public sealed class ActionButton : Button {
        private bool hover, pressed, busy;
        private int angle;
        private readonly Timer animation = new Timer();
        public bool Busy {
            get { return busy; }
            set { if(busy==value)return; busy=value; animation.Enabled=busy && Visible; Invalidate(); }
        }
        public ActionButton() {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw,true);
            FlatStyle=FlatStyle.Flat; FlatAppearance.BorderSize=0; UseVisualStyleBackColor=false;
            animation.Interval=60; animation.Tick+=delegate { angle=(angle+24)%360; Invalidate(); };
        }
        protected override void OnVisibleChanged(EventArgs e) { base.OnVisibleChanged(e); animation.Enabled=busy && Visible; }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnMouseEnter(EventArgs e) { hover=true; base.OnMouseEnter(e); Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { hover=false; pressed=false; base.OnMouseLeave(e); Invalidate(); }
        protected override void OnMouseDown(MouseEventArgs e) { pressed=true; base.OnMouseDown(e); Invalidate(); }
        protected override void OnMouseUp(MouseEventArgs e) { pressed=false; base.OnMouseUp(e); Invalidate(); }
        protected override void OnPaint(PaintEventArgs e) {
            Graphics g=e.Graphics; g.SmoothingMode=SmoothingMode.AntiAlias;
            g.Clear(Parent==null ? BackColor : Parent.BackColor);
            Color fill=Enabled ? (pressed ? ControlPaint.Dark(BackColor,0.10f) : hover ? ControlPaint.Light(BackColor,0.08f) : BackColor) : Color.FromArgb(39,49,63);
            Color text=Enabled ? ForeColor : Color.FromArgb(170,183,198);
            float radius=Math.Max(6,Font.Size*0.7f), diameter=radius*2;
            RectangleF box=new RectangleF(0.5f,0.5f,Math.Max(1,Width-1.5f),Math.Max(1,Height-1.5f));
            using(GraphicsPath path=new GraphicsPath()) {
                path.AddArc(box.Left,box.Top,diameter,diameter,180,90);
                path.AddArc(box.Right-diameter,box.Top,diameter,diameter,270,90);
                path.AddArc(box.Right-diameter,box.Bottom-diameter,diameter,diameter,0,90);
                path.AddArc(box.Left,box.Bottom-diameter,diameter,diameter,90,90); path.CloseFigure();
                using(Brush brush=new SolidBrush(fill))g.FillPath(brush,path);
                using(Pen pen=new Pen(Focused ? Color.FromArgb(96,205,255) : Color.FromArgb(55,69,87),Focused ? 2f : 1f))g.DrawPath(pen,path);
            }
            int margin=Math.Max(10,(int)(Font.Size*1.2));
            Rectangle caption=new Rectangle(margin,0,Math.Max(1,Width-margin*2-(busy ? 28 : 0)),Height);
            TextRenderer.DrawText(g,Text,Font,caption,text,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine|TextFormatFlags.EndEllipsis|TextFormatFlags.NoPrefix);
            if(busy) {
                int size=Math.Max(14,(int)(Font.Size*1.5));
                using(Pen pen=new Pen(text,2f)) { pen.StartCap=LineCap.Round;pen.EndCap=LineCap.Round;g.DrawArc(pen,Width-margin-size,(Height-size)/2,size,size,angle,250); }
            }
        }
        protected override void Dispose(bool disposing) { if(disposing)animation.Dispose();base.Dispose(disposing); }
    }
}
