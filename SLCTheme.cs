// SLCTheme.cs -- SimpleLootCouncil's look, for the SLCLauncher window.
//
// The palette is SimpleLootCouncil's own (UI/Style.lua in that addon), so the
// launcher and the addon read as one product: a near-black slate canvas,
// controls a step lighter with steel hairline borders, recessed insets for
// anything you tick, and ONE blue accent, spent on state -- a ticked box, the
// primary button. Hex values are copied from Style.lua's comments; where that
// file says "white at an alpha", the value here is that alpha composited over
// the canvas, because GDI+ text has no ground to blend against.
//
// WinForms' stock controls cannot be themed this far -- a GroupBox's etched
// border, a CheckBox's glyph and a Button's bevel are drawn by the system -- so
// the few the window needs are drawn here instead. Compiled into
// SLCLauncher.exe by the installer; SLCLauncherSettings.ps1 loads this file
// itself only when run outside the exe.

using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace SLCLauncher.Theme
{
    public static class Palette
    {
        static Color Hex(int rgb) { return Color.FromArgb((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF); }

        public static readonly Color Canvas        = Hex(0x0D1217); // canvas
        public static readonly Color Band          = Hex(0x0B0F14); // title band, footer
        public static readonly Color HeaderTop     = Hex(0x171C1E);
        public static readonly Color HeaderBottom  = Hex(0x10151A);
        public static readonly Color Card          = Hex(0x0F151A); // a card on the canvas
        public static readonly Color Inset         = Hex(0x0B1014); // black 25% over a card
        public static readonly Color Control       = Hex(0x10181E); // button rest
        public static readonly Color ControlHover  = Hex(0x19262F);
        public static readonly Color ControlDown   = Hex(0x090E12);
        public static readonly Color Rule          = Hex(0x1C272E); // between rows
        public static readonly Color Edge          = Hex(0x202B32); // panel edge
        public static readonly Color Steel         = Hex(0x30404A); // control border
        public static readonly Color SteelBright   = Hex(0x34454E); // hover / focus
        public static readonly Color WindowEdge    = Hex(0x38464E);
        public static readonly Color Text          = Hex(0xFFFFFF);
        public static readonly Color TextMuted     = Hex(0x8D9092); // white 53%
        public static readonly Color TextFaint     = Hex(0x707376); // white 41%
        public static readonly Color Accent        = Hex(0x478CEB);
        public static readonly Color AccentHover   = Hex(0x5A99EE);
        public static readonly Color AccentDim     = Hex(0x3162A7); // pressed accent
        public static readonly Color ScrollThumb   = Hex(0x31363A); // white 14% over a card
        public static readonly Color Bad           = Hex(0xE57373);
        public static readonly Color Notice        = Hex(0xF0A030); // "update available"
    }

    static class Dpi
    {
        public static int Scale(Control c, int px)
        {
            using (var g = c.CreateGraphics()) { return (int)Math.Round(px * g.DpiX / 96f); }
        }
    }

    static class Surface
    {
        // The colour actually behind a control. Layout panels are transparent,
        // and clearing to Color.Transparent paints black -- so walk up to the
        // first ancestor that is a real surface: a card, a band, the window.
        public static Color Behind(Control c)
        {
            for (var p = c.Parent; p != null; p = p.Parent)
                if (p.BackColor.A == 255) return p.BackColor;
            return Palette.Canvas;
        }
    }

    // A square box with a one-pixel steel edge: recessed when clear, filled
    // with the accent and a white tick when set. Square, not rounded -- in SLC
    // only window surfaces round; controls sitting on them do not.
    public class ThemedCheckBox : CheckBox
    {
        bool hover;

        public ThemedCheckBox()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            ForeColor = Palette.Text;
            BackColor = Color.Transparent;
            AutoSize  = true;
            Cursor    = Cursors.Hand;
        }

        int Box { get { return Dpi.Scale(this, 16); } }
        int Gap { get { return Dpi.Scale(this, 9); } }

        public override Size GetPreferredSize(Size proposed)
        {
            var t = TextRenderer.MeasureText(Text, Font, Size.Empty, TextFormatFlags.NoPadding);
            return new Size(Box + Gap + t.Width + Dpi.Scale(this, 2),
                            Math.Max(Box, t.Height) + Dpi.Scale(this, 8));
        }

        protected override void OnMouseEnter(EventArgs e) { hover = true;  Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Surface.Behind(this));

            int box = Box;
            var r = new Rectangle(0, (Height - box) / 2, box - 1, box - 1);
            bool on = Checked, live = Enabled;

            using (var fill = new SolidBrush(on ? (live ? Palette.Accent : Palette.AccentDim) : Palette.Inset))
                g.FillRectangle(fill, r);
            Color edge = on ? (live ? Palette.Accent : Palette.AccentDim)
                            : (hover || Focused) && live ? Palette.SteelBright : Palette.Steel;
            using (var pen = new Pen(edge)) g.DrawRectangle(pen, r);

            if (on)
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                float s = box / 16f;
                using (var pen = new Pen(live ? Color.White : Palette.TextMuted, 2f * s))
                {
                    pen.StartCap = pen.EndCap = LineCap.Round;
                    pen.LineJoin = LineJoin.Round;
                    g.DrawLines(pen, new[] {
                        new PointF(r.X + 3.8f * s, r.Y + 8.2f * s),
                        new PointF(r.X + 6.6f * s, r.Y + 11f * s),
                        new PointF(r.X + 12f * s,  r.Y + 5f * s) });
                }
                g.SmoothingMode = SmoothingMode.None;
            }

            var textRect = new Rectangle(box + Gap, 0, Width - box - Gap, Height);
            TextRenderer.DrawText(g, Text, Font, textRect,
                live ? ForeColor : Palette.TextFaint,
                TextFormatFlags.VerticalCenter | TextFormatFlags.Left |
                TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis);
        }
    }

    // A flat button: control fill, steel edge, a step lighter on hover and
    // darker when pressed. Primary is the accent, and there is only ever one.
    public class ThemedButton : Button
    {
        bool hover, down;
        public bool Primary { get; set; }
        // Draws a centred cross instead of the text: a close or remove button.
        public bool Cross { get; set; }

        public ThemedButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            ForeColor = Palette.Text;
            AutoSize  = true;
            Cursor    = Cursors.Hand;
        }

        public override Size GetPreferredSize(Size proposed)
        {
            var t = TextRenderer.MeasureText(Text, Font, Size.Empty, TextFormatFlags.NoPadding);
            return new Size(t.Width + Dpi.Scale(this, 44), Math.Max(t.Height + Dpi.Scale(this, 12), Dpi.Scale(this, 30)));
        }

        protected override void OnMouseEnter(EventArgs e) { hover = true;  Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { down = true; Invalidate(); } base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnEnabledChanged(EventArgs e) { Cursor = Enabled ? Cursors.Hand : Cursors.Default; base.OnEnabledChanged(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Surface.Behind(this));
            var r = new Rectangle(0, 0, Width - 1, Height - 1);
            bool live = Enabled;

            Color fill, edge;
            if (Primary && live)
            {
                fill = down ? Palette.AccentDim : hover ? Palette.AccentHover : Palette.Accent;
                edge = fill;
            }
            else
            {
                fill = !live ? Palette.Control : down ? Palette.ControlDown : hover ? Palette.ControlHover : Palette.Control;
                edge = live && (hover || Focused) ? Palette.SteelBright : Palette.Steel;
            }
            using (var b = new SolidBrush(fill)) g.FillRectangle(b, r);
            using (var p = new Pen(edge)) g.DrawRectangle(p, r);
            if (Focused && ShowFocusCues && live)
                using (var p = new Pen(Primary ? Color.White : Palette.Accent)) g.DrawRectangle(p, Rectangle.Inflate(r, -2, -2));

            if (Cross)
            {
                // Two strokes about the box's exact centre: a glyph's side
                // bearings leave a text "x" visibly off centre in a small box.
                float c = (Width - 1) / 2f, m = (Height - 1) / 2f, h = Math.Min(Width, Height) * 0.2f;
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (var p = new Pen(live ? ForeColor : Palette.TextFaint, Math.Max(1.5f, Dpi.Scale(this, 3) / 2f)))
                {
                    p.StartCap = p.EndCap = LineCap.Round;
                    g.DrawLine(p, c - h, m - h, c + h, m + h);
                    g.DrawLine(p, c - h, m + h, c + h, m - h);
                }
                g.SmoothingMode = SmoothingMode.None;
                return;
            }
            TextRenderer.DrawText(g, Text, Font, r, live ? ForeColor : Palette.TextFaint,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
    }

    // SLC's scrollbar (S.ScrollBar in Style.lua): no track, no arrows, just a
    // 6px thumb 36px tall in white at 14%, the dim accent while the pointer is
    // on it. Hidden whenever there is nothing to scroll. Drag the thumb, or
    // click above or below it to bring it there.
    public class SlimScrollBar : Control
    {
        int maximum, value, dragOffset;
        bool hover, dragging;
        public event EventHandler ValueChanged;

        public SlimScrollBar()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Visible   = false;
        }

        int ThumbHeight { get { return Math.Min(Height, Dpi.Scale(this, 36)); } }

        public int Maximum
        {
            get { return maximum; }
            set
            {
                maximum = Math.Max(0, value);
                Visible = maximum > 0;
                if (this.value > maximum) Value = maximum;
                Invalidate();
            }
        }

        public int Value
        {
            get { return value; }
            set
            {
                int v = Math.Max(0, Math.Min(maximum, value));
                if (v == this.value) return;
                this.value = v;
                Invalidate();
                if (ValueChanged != null) ValueChanged(this, EventArgs.Empty);
            }
        }

        Rectangle Thumb
        {
            get
            {
                int track = Height - ThumbHeight;
                int y = maximum > 0 ? (int)Math.Round((double)value * track / maximum) : 0;
                return new Rectangle(0, y, Width, ThumbHeight);
            }
        }

        void MoveThumbTo(int top)
        {
            int track = Height - ThumbHeight;
            if (track <= 0) return;
            top = Math.Max(0, Math.Min(track, top));
            Value = (int)Math.Round((double)top * maximum / track);
        }

        protected override void OnMouseEnter(EventArgs e) { hover = true;  Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                if (!Thumb.Contains(e.Location)) MoveThumbTo(e.Y - ThumbHeight / 2);
                dragging   = true;
                dragOffset = e.Y - Thumb.Y;
                Capture    = true;
                Invalidate();
            }
            base.OnMouseDown(e);
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            if (dragging) MoveThumbTo(e.Y - dragOffset);
            base.OnMouseMove(e);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            dragging = false;
            Capture  = false;
            Invalidate();
            base.OnMouseUp(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(Surface.Behind(this));
            using (var b = new SolidBrush(hover || dragging ? Palette.AccentDim : Palette.ScrollThumb))
                e.Graphics.FillRectangle(b, Thumb);
        }
    }

    // A window onto taller content, with SLC's scrollbar beside it (as
    // S.ScrollRegion): the content scrolls, whatever heads it stays outside.
    // The wheel moves two Steps a notch, and tabbing to a control out of view
    // brings it into view.
    public class ScrollView : Panel
    {
        readonly Panel viewport;
        readonly SlimScrollBar bar;
        Control content;

        public int Step { get; set; }

        public ScrollView()
        {
            DoubleBuffered = true;
            BackColor = Color.Transparent;
            viewport  = new Panel { BackColor = Color.Transparent, Margin = Padding.Empty };
            bar       = new SlimScrollBar();
            Controls.Add(viewport);
            Controls.Add(bar);
            bar.ValueChanged += delegate { if (content != null) content.Top = -bar.Value; };
        }

        public void SetContent(Control c)
        {
            content = c;
            c.Location = Point.Empty;
            viewport.Controls.Add(c);
            Watch(c);
            c.SizeChanged += delegate { Reconcile(); };
            Reconcile();
        }

        void Watch(Control c)
        {
            foreach (Control k in c.Controls)
            {
                k.Enter += delegate(object s, EventArgs e) { ScrollIntoView((Control)s); };
                Watch(k);
            }
        }

        public void ScrollIntoView(Control k)
        {
            if (content == null) return;
            int top = content.PointToClient(k.PointToScreen(Point.Empty)).Y;
            if (top < bar.Value) bar.Value = top;
            else if (top + k.Height > bar.Value + viewport.Height) bar.Value = top + k.Height - viewport.Height;
        }

        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e);
            int w = Dpi.Scale(this, 6), gap = Dpi.Scale(this, 3);
            bar.SetBounds(Width - w, 0, w, Height);
            viewport.SetBounds(0, 0, Math.Max(0, Width - w - gap), Height);
            Reconcile();
        }

        void Reconcile()
        {
            if (content == null) return;
            bar.Maximum = Math.Max(0, content.Height - viewport.Height);
            content.Top = -bar.Value;
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            int step = Step > 0 ? Step : Dpi.Scale(this, 32);
            // A wheel notch is 120; a touchpad sends smaller amounts more often.
            bar.Value = bar.Value - (int)Math.Round(e.Delta * step * 2 / 120.0);
            var h = e as HandledMouseEventArgs;
            if (h != null) h.Handled = true;
            base.OnMouseWheel(e);
        }
    }

    // A card: a surface one step up from the canvas, edged with a hairline.
    public class Card : Panel
    {
        public Card()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
            BackColor = Palette.Card;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using (var p = new Pen(Palette.Edge)) e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
        }
    }

    // The title band: its own small gradient, with a rule under it.
    public class HeaderBand : Panel
    {
        public HeaderBand()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
            BackColor = Palette.HeaderBottom;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            if (Width > 0 && Height > 0)
                using (var b = new LinearGradientBrush(ClientRectangle, Palette.HeaderTop, Palette.HeaderBottom, 90f))
                    e.Graphics.FillRectangle(b, ClientRectangle);
            using (var p = new Pen(Palette.Edge)) e.Graphics.DrawLine(p, 0, Height - 1, Width, Height - 1);
        }
    }

    // One tab in the header's strip of game versions: its name, muted at rest,
    // white on hover, and white over a bar of the accent when it is the one
    // shown. The bar sits on the header's bottom rule, as a tab's edge would.
    // Transparent, so the header's gradient shows behind it.
    public class TabButton : Control
    {
        bool hover, selected;

        public bool Selected
        {
            get { return selected; }
            set { selected = value; Invalidate(); }
        }

        public TabButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            SetStyle(ControlStyles.Selectable, false);
            BackColor = Color.Transparent;
            ForeColor = Palette.Text;
            Cursor    = Cursors.Hand;
        }

        public override Size GetPreferredSize(Size proposed)
        {
            var t = TextRenderer.MeasureText(Text, Font, Size.Empty, TextFormatFlags.NoPadding);
            return new Size(t.Width + Dpi.Scale(this, 28), t.Height + Dpi.Scale(this, 18));
        }

        protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
        protected override void OnMouseEnter(EventArgs e) { hover = true;  Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            if (selected)
            {
                using (var b = new SolidBrush(Color.FromArgb(18, Palette.Accent)))
                    g.FillRectangle(b, 0, 0, Width, Height);
                using (var b = new SolidBrush(Palette.Accent))
                    g.FillRectangle(b, 0, Height - Dpi.Scale(this, 2), Width, Dpi.Scale(this, 2));
            }
            else if (hover)
            {
                using (var b = new SolidBrush(Color.FromArgb(10, Color.White)))
                    g.FillRectangle(b, 0, 0, Width, Height);
            }
            Color ink = selected || hover ? Palette.Text : Palette.TextMuted;
            TextRenderer.DrawText(g, Text, Font, new Rectangle(0, 0, Width, Height - Dpi.Scale(this, 2)), ink,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
    }

    // The footer: the band colour, with a rule over it.
    public class FooterBand : Panel
    {
        public FooterBand()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
            BackColor = Palette.Band;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using (var p = new Pen(Palette.Edge)) e.Graphics.DrawLine(p, 0, 0, Width, 0);
        }
    }

    // The window itself, with no Windows title bar: the header band is the
    // title bar instead, carrying its own minimize and close buttons and
    // dragging the window wherever it is not a control.
    //
    // A window with no border loses three things the title bar gave it, and
    // they are put back here: its taskbar button minimizing and restoring it
    // and offering a window menu (WS_MINIMIZEBOX, WS_SYSMENU), a shadow
    // (CS_DROPSHADOW), and on Windows 11 its rounded corners. Its one-pixel
    // edge is the window's own colour showing round the page, which the
    // Padding of one leaves uncovered.
    public class ThemedWindow : Form
    {
        const int WS_MINIMIZEBOX = 0x00020000;
        const int WS_SYSMENU     = 0x00080000;
        const int CS_DROPSHADOW  = 0x00020000;
        const int WS_EX_COMPOSITED = 0x02000000;

        public ThemedWindow()
        {
            FormBorderStyle = FormBorderStyle.None;
            BackColor       = Palette.WindowEdge;
            Padding         = new Padding(1);
        }

        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                cp.Style     |= WS_MINIMIZEBOX | WS_SYSMENU;
                cp.ClassStyle |= CS_DROPSHADOW;
                // Every control in the window painted into one buffer and put
                // on screen at once: the see-through labels and boxes would
                // otherwise each be seen clearing to the card and redrawing.
                cp.ExStyle   |= WS_EX_COMPOSITED;
                return cp;
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            Native.RoundCorners(this);
        }
    }

    // Minimize or close, drawn as Windows 11 draws its own: a flat cell flush
    // with the window's top right corner, lit on hover, the close cell red.
    public class CaptionButton : Control
    {
        bool hover, down;
        public bool IsClose { get; set; }

        public CaptionButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            SetStyle(ControlStyles.Selectable, false);   // not a tab stop: Alt+F4 and the taskbar cover the keyboard
        }

        static readonly Color CloseHover = Color.FromArgb(0xC4, 0x2B, 0x1C);
        static readonly Color CloseDown  = Color.FromArgb(0x94, 0x1F, 0x14);

        protected override void OnMouseEnter(EventArgs e) { hover = true;  Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { down = true; Invalidate(); } base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }

        protected override void OnClick(EventArgs e)
        {
            base.OnClick(e);
            var form = FindForm();
            if (form == null) return;
            // The window menu's own commands, so Windows minimizes and closes
            // it exactly as from the taskbar -- setting WindowState does
            // nothing to a window shown with ShowDialog.
            Native.SystemCommand(form, IsClose ? Native.SC_CLOSE : Native.SC_MINIMIZE);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            Color fill = Color.Empty;
            if (IsClose && (hover || down)) fill = down ? CloseDown : CloseHover;
            else if (down)  fill = Palette.ControlDown;
            else if (hover) fill = Palette.ControlHover;
            if (fill.IsEmpty)
                using (var b = new LinearGradientBrush(new Rectangle(0, -Top, Width, Parent.Height),
                                                       Palette.HeaderTop, Palette.HeaderBottom, 90f))
                    g.FillRectangle(b, ClientRectangle);   // the header's own gradient, so the cell is invisible at rest
            else
                using (var b = new SolidBrush(fill)) g.FillRectangle(b, ClientRectangle);

            // A ten-pixel glyph, centred, one pixel thick at any scale but 2x.
            float s = Dpi.Scale(this, 100) / 100f;
            float half = 5f * s, cx = Width / 2f, cy = Height / 2f;
            Color ink = (IsClose && (hover || down)) ? Color.White : (hover ? Palette.Text : Palette.TextMuted);
            using (var pen = new Pen(ink, Math.Max(1f, (float)Math.Floor(s))))
            {
                if (IsClose)
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.DrawLine(pen, cx - half, cy - half, cx + half, cy + half);
                    g.DrawLine(pen, cx - half, cy + half, cx + half, cy - half);
                }
                else
                {
                    g.DrawLine(pen, cx - half, cy, cx + half, cy);
                }
            }
        }
    }

    public static class Native
    {
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
        [DllImport("user32.dll")] static extern bool ReleaseCapture();
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
        const int DWMWA_BORDER_COLOR  = 34;
        const int DWMWCP_ROUND        = 2;
        const int WM_NCLBUTTONDOWN    = 0xA1;
        const int HTCAPTION           = 2;
        const int WM_SYSCOMMAND       = 0x112;
        public const int SC_MINIMIZE  = 0xF020;
        public const int SC_CLOSE     = 0xF060;

        // Posted, not sent: from inside a click the button still holds the
        // mouse capture, and Windows ignores the command until it lets go.
        // Posted, it runs once the click has finished.
        public static void SystemCommand(Form form, int command)
        {
            PostMessage(form.Handle, WM_SYSCOMMAND, (IntPtr)command, IntPtr.Zero);
        }

        static int ColorRef(Color c) { return c.R | (c.G << 8) | (c.B << 16); }

        // Windows 11 rounds a window's corners only when asked, once it has no
        // title bar. Windows 10 does not know the attribute and refuses it,
        // which leaves square corners -- what every window there has anyway.
        public static void RoundCorners(Form form)
        {
            int round = DWMWCP_ROUND, border = ColorRef(Palette.WindowEdge);
            DwmSetWindowAttribute(form.Handle, DWMWA_WINDOW_CORNER_PREFERENCE, ref round, 4);
            DwmSetWindowAttribute(form.Handle, DWMWA_BORDER_COLOR, ref border, 4);
        }

        [DllImport("user32.dll")] static extern bool RedrawWindow(IntPtr hWnd, IntPtr rect, IntPtr region, int flags);
        const int WM_SETREDRAW = 0x000B;
        const int RDW_INVALIDATE = 0x0001, RDW_ERASE = 0x0004, RDW_ALLCHILDREN = 0x0080, RDW_UPDATENOW = 0x0100;

        // Stops a control and everything in it drawing, so a change made in
        // several steps -- one panel hidden, another shown -- is never seen
        // half done. Thaw draws the finished result in one pass.
        public static void Freeze(Control c)
        {
            SendMessage(c.Handle, WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero);
        }

        public static void Thaw(Control c)
        {
            SendMessage(c.Handle, WM_SETREDRAW, (IntPtr)1, IntPtr.Zero);
            RedrawWindow(c.Handle, IntPtr.Zero, IntPtr.Zero,
                         RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW);
        }

        // Pressing the mouse on this control drags the window, exactly as on a
        // title bar: Windows is told the press landed on its caption and does
        // the rest, Aero Snap included.
        public static void DragsWindow(Control surface)
        {
            surface.MouseDown += delegate(object sender, MouseEventArgs e)
            {
                if (e.Button != MouseButtons.Left) return;
                var form = ((Control)sender).FindForm();
                if (form == null) return;
                ReleaseCapture();
                SendMessage(form.Handle, WM_NCLBUTTONDOWN, (IntPtr)HTCAPTION, IntPtr.Zero);
            };
        }
    }
}
