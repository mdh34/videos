

namespace Audience{
    
    public const string [] video = {
    "mpg",
    "flv",
    "mp4"
    };
    public const string [] audio = {
    "mp3",
    "ogg"
    };
    
    public static string get_extension (string filename){
        int i=0;
        for (i=filename.length;i!=0;i--){
            if (filename [i] == '.')
                break;
        }
        return filename.substring (i+1);
    }
    public static string get_basename (string filename){
        int i=0;
        for (i=filename.length;i!=0;i--){
            if (filename [i] == '.')
                break;
        }
        int j=0;
        for (j=filename.length;j!=0;j--){
            if (filename[j] == '/')
                break;
        }
        return filename.substring (j + 1, i - j - 1);
    }
    
    public static string seconds_to_time (int secs){
        int hours = 0;
        int min = 0;
        while (secs >= 60){
            ++min;
            secs -= 60;
        }
        int min_tmp = min;
        while (min >= 60){
            ++hours;
            min_tmp -= 60;
        }
        string seconds = (secs < 10)?"0"+secs.to_string ():secs.to_string ();
        
        string ret = (hours > 0)?hours.to_string ():"";
        ret += min.to_string () + ":" + seconds;
        return ret;
    }
    
    class LLabel : Gtk.Label{
        public LLabel (string label){
            this.set_halign (Gtk.Align.START);
            this.label = label;
        }
        public LLabel.indent (string label){
            this (label);
            this.margin_left = 10;
        }
        public LLabel.markup (string label){
            this (label);
            this.use_markup = true;
        }
        public LLabel.right (string label){
            this.set_halign (Gtk.Align.END);
            this.label = label;
        }
        public LLabel.right_with_markup (string label){
            this.set_halign (Gtk.Align.END);
            this.use_markup = true;
            this.label = label;
        }
    }
    
    public class AudienceApp : Granite.Application{
        
        construct{
            program_name = "Audience";
            exec_name = "audience";
            
            build_data_dir = Constants.DATADIR;
            build_pkg_data_dir = Constants.PKGDATADIR;
            build_release_name = Constants.RELEASE_NAME;
            build_version = Constants.VERSION;
            build_version_info = Constants.VERSION_INFO;
            
            app_years = "2011-2012";
            app_icon = "audience";
            app_launcher = "audience.desktop";
            application_id = "net.launchpad.audience";
            
            main_url = "https://code.launchpad.net/audience";
            bug_url = "https://bugs.launchpad.net/audience";
            help_url = "https://code.launchpad.net/audience";
            translate_url = "https://translations.launchpad.net/audience";
            
            /*about_authors = {""};
            about_documenters = {""};
            about_artists = {""};
            about_translators = "Launchpad Translators";
            about_comments = "To be determined"; */
            about_license_type = Gtk.License.GPL_3_0;
        }
        
        public ClutterGst.VideoTexture    canvas;
        public Gtk.Window                 mainwindow;
        public Audience.Widgets.TagView   tagview;
        public Gtk.Scale                  slider;
        public Audience.Widgets.Previewer previewer;
        public GtkClutter.Actor           bar;
        public Gtk.Toolbar                toolbar;
        public Gtk.ToolButton             play;
        public Gtk.ToolButton             pause;
        public Gtk.ToolButton             unfullscreen;
        public Clutter.Stage              stage;
        public bool                       fullscreened;
        public uint                       hiding_timer;
        
        private float video_w;
        private float video_h;
        private bool  just_opened;
        private bool  reached_end;
        
        private Gdk.Cursor normal_cursor;
        private Gdk.Cursor blank_cursor;
        
        private inline Gtk.Image? sym (string name){
            try{
            return new Gtk.Image.from_pixbuf (Gtk.IconTheme.get_default ().lookup_icon 
                (name, 24, 0).load_symbolic ({1.0,1.0,1.0,1.0}, null, null, null, null));
            }catch (Error e){warning (e.message);return null;}
        }
        
        public AudienceApp (){
            Granite.Services.Logger.DisplayLevel = Granite.Services.LogLevel.DEBUG;
            
            this.flags |= GLib.ApplicationFlags.HANDLES_OPEN;
            
            this.fullscreened = false;
            
            this.canvas     = new ClutterGst.VideoTexture ();
            this.mainwindow = new Gtk.Window ();
            this.tagview    = new Audience.Widgets.TagView (this);
            this.previewer  = new Audience.Widgets.Previewer ();
            this.bar        = new GtkClutter.Actor ();
            this.toolbar    = new Gtk.Toolbar ();
            var mainbox     = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var clutter     = new GtkClutter.Embed ();
            this.stage      = (Clutter.Stage)clutter.get_stage ();
            this.play       = new Gtk.ToolButton (sym ("media-playback-start-symbolic"), "");
            this.pause      = new Gtk.ToolButton (sym ("media-playback-pause-symbolic"), "");
            var time_item   = new Gtk.ToolItem ();
            var slider_item = new Gtk.ToolItem ();
            var remain_item = new Gtk.ToolItem ();
            var volm        = new Gtk.ToolItem ();
            var info        = new Gtk.ToggleToolButton ();
            var open        = new Gtk.ToolButton (sym ("document-export-symbolic"),"");
            var menu        = new Gtk.Menu ();
            var appm        = this.create_appmenu (menu);
            this.slider     = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 100, 1);
            var volume      = new Gtk.VolumeButton ();
            var time        = new Gtk.Label ("0");
            var remaining   = new Gtk.Label ("0");
            this.unfullscreen = new Gtk.ToolButton (
                new Gtk.Image.from_stock (Gtk.Stock.LEAVE_FULLSCREEN, Gtk.IconSize.BUTTON), "");
            this.blank_cursor  = new Gdk.Cursor (Gdk.CursorType.BLANK_CURSOR);
            this.normal_cursor = this.mainwindow.get_window ().get_cursor ();
            
            /*UI*/
            this.canvas.reactive = true;
            this.canvas.width    = 654;
            this.canvas.height   = 352;
            
            stage.add_actor (canvas);
            stage.add_actor (tagview);
            stage.add_actor (previewer);
            stage.add_actor (bar);
            stage.color = Clutter.Color.from_string ("#000");
            
            this.tagview.x      = stage.width;
            this.tagview.width  = 350;
            
            this.mainwindow.set_application (this);
            this.mainwindow.add (mainbox);
            this.mainwindow.set_default_size (654, 352);
            
            slider_item.set_expand (true);
            slider_item.add (slider);
            slider.draw_value = false;
            
            volm.add (volume);
            volume.use_symbolic = true;
            
            time_item.add (time);
            remain_item.add (remaining);
            
            info.icon_widget = sym ("view-list-filter-symbolic");
            appm.icon_widget = sym ("document-properties-symbolic");
            
            play.sensitive = false;
            
            play.margin = time_item.margin = slider_item.margin = pause.margin = 
            volm.margin = info.margin = open.margin = appm.margin = 5;
            
            toolbar.insert (play, -1);
            toolbar.insert (time_item,   -1);
            toolbar.insert (slider_item, -1);
            toolbar.insert (remain_item, -1);
            toolbar.insert (volm, -1);
            toolbar.insert (info, -1);
            toolbar.insert (open, -1);
            toolbar.insert (appm, -1);
            
            var css = new Gtk.CssProvider ();
            try{
            css.load_from_data ("
                *{
                    background-color:rgba(0,0,0,0);
                    background-image:none;
                    color:white;
                }
                ", -1);
            }catch (Error e){warning (e.message);}
            toolbar.get_style_context ().add_provider (css, 12000);
            remaining.get_style_context ().add_provider (css, 12000);
            time.get_style_context ().add_provider (css, 12000);
            
            bar.get_widget ().draw.connect ( (ctx) => {
                ctx.set_operator (Cairo.Operator.SOURCE);
                ctx.rectangle (0, 0, bar.get_widget ().get_allocated_width  (), 
                                     bar.get_widget ().get_allocated_height ());
                ctx.set_source_rgba (0.0, 0.0, 0.0, 0.8);
                ctx.fill ();
                return false;
            });
            
            toolbar.show_all ();
            ((Gtk.Container)bar.get_widget ()).add (toolbar);
            
            mainbox.pack_start (clutter);
            
            this.previewer.get_pipeline ().set_state (Gst.State.PLAYING);
            
            /*events*/
            //end
            this.canvas.eos.connect ( () => {
                reached_end = true;
                this.toggle_play (false);
            });
            
            //slider
            ulong id = slider.value_changed.connect ( () => {
                canvas.progress = slider.get_value () / canvas.duration;
            });
            Timeout.add (1000, () => {
                SignalHandler.block (slider, id);
                slider.set_range (0, canvas.duration);
                slider.set_value (canvas.duration * canvas.progress);
                SignalHandler.unblock (slider, id);
                
                time.label = seconds_to_time ((int)slider.get_value ());
                
                remaining.label = "-" + seconds_to_time ((int)(canvas.duration - 
                    slider.get_value ()));
                return true;
            });
            
            //volume
            volume.value_changed.connect ( () => {
                canvas.audio_volume = volume.value;
            });
            volume.value = 1.0;
            
            //preview thing
            slider.motion_notify_event.connect ( (e) => {
                previewer.x = (float)e.x;
                previewer.y = stage.height - 180;
                Timeout.add (200, () => {
                    previewer.progress = e.x / slider.get_allocated_width ();
                    return false;
                });
                return false;
            });
            slider.enter_notify_event.connect ( (e) => {
                previewer.get_pipeline ().set_state (Gst.State.PLAYING);
                var o2 = 255;
                previewer.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 400, opacity:o2);
                previewer.raise_top ();
                return false;
            });
            slider.leave_notify_event.connect ( (e) => {
                var o2 = 0;
                previewer.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 400, opacity:o2);
                previewer.get_pipeline ().set_state (Gst.State.PAUSED);
                Timeout.add (400, () => {previewer.lower_bottom ();return false;});
                return false;
            });
            
            /*slide controls back in*/
            this.mainwindow.motion_notify_event.connect ( () => {
                float y2 = this.stage.height - 56;
                this.bar.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 100, y:y2);
                this.mainwindow.get_window ().set_cursor (normal_cursor);
                Gst.State state;
                canvas.get_pipeline ().get_state (out state, null, 0);
                if (state == Gst.State.PLAYING){
                    Source.remove (this.hiding_timer);
                    this.hiding_timer = GLib.Timeout.add (2000, () => {
                        this.mainwindow.get_window ().set_cursor (blank_cursor);
                        float y3 = this.stage.height;
                        this.bar.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 1000, y:y3);
                        return false;
                    });
                }
                return false;
            });
            
            /*open location popover*/
            open.clicked.connect ( () => {
                var pop = new Granite.Widgets.PopOver ();
                var box = new Gtk.Grid ();
                ((Gtk.Box)pop.get_content_area ()).add (box);
                
                box.row_spacing    = 5;
                box.column_spacing = 12;
                
                var fil   = new Gtk.Button.with_label ("File");
                var fil_i = new Gtk.Image.from_stock (Gtk.Stock.OPEN, Gtk.IconSize.DND);
                var cd    = new Gtk.Button.with_label ("CD");
                var cd_i  = new Gtk.Image.from_icon_name ("media-cdrom-audio", Gtk.IconSize.DND);
                var dvd   = new Gtk.Button.with_label ("DVD");
                var dvd_i = new Gtk.Image.from_icon_name ("media-cdrom", Gtk.IconSize.DND);
                var net   = new Gtk.Button.with_label ("Network File");
                var net_i = new Gtk.Image.from_icon_name ("internet-web-browser", Gtk.IconSize.DND);
                
                fil.clicked.connect ( () => {
                    pop.destroy ();
                    var file = new Gtk.FileChooserDialog ("Open", this.mainwindow, Gtk.FileChooserAction.OPEN,
                        Gtk.Stock.OPEN, Gtk.ResponseType.ACCEPT,
                        Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL);
                    if (file.run () == Gtk.ResponseType.ACCEPT){
                        open_file (file.get_uri ());
                    }
                    file.destroy ();
                });
                cd.clicked.connect ( () => {
                    open_file ("cdda://");
                    canvas.get_pipeline ().set_state (Gst.State.PLAYING);
                    pop.destroy ();
                });
                dvd.clicked.connect ( () => {
                    open_file ("dvd://");
                    canvas.get_pipeline ().set_state (Gst.State.PLAYING);
                    pop.destroy ();
                });
                net.clicked.connect ( () => {
                    var entry = new Gtk.Entry ();
                    entry.secondary_icon_stock = Gtk.Stock.OPEN;
                    entry.icon_release.connect ( (pos, e) => {
                        open_file (entry.text);
                        canvas.get_pipeline ().set_state (Gst.State.PLAYING);
                        pop.destroy ();
                    });
                    box.remove (net);
                    box.attach (entry, 1, 3, 1, 1);
                    entry.show ();
                });
                
                box.attach (fil_i, 0, 0, 1, 1);
                box.attach (fil,   1, 0, 1, 1);
                box.attach (dvd_i, 0, 1, 1, 1);
                box.attach (dvd,   1, 1, 1, 1);
                box.attach (cd_i,  0, 2, 1, 1);
                box.attach (cd,    1, 2, 1, 1);
                box.attach (net_i, 0, 3, 1, 1);
                box.attach (net,   1, 3, 1, 1);
                
                pop.move_to_widget (open);
                pop.show_all ();
                pop.present ();
                pop.run ();
                pop.destroy ();
            });
            
            play.clicked.connect  ( () => {toggle_play (true);});
            pause.clicked.connect ( () => {toggle_play (false);});
            
            unfullscreen.clicked.connect (toggle_fullscreen);
            
            info.toggled.connect ( () => {
                if (info.active)
                    tagview.expand ();
                else
                    tagview.collapse ();
            });
            
            //fullscreen on maximize
            this.mainwindow.window_state_event.connect ( (e) => {
                if (!((e.window.get_state () & Gdk.WindowState.MAXIMIZED) == 0) && !this.fullscreened){
                    this.mainwindow.fullscreen ();
                    this.fullscreened = true;
                    toolbar.insert (unfullscreen, 4);
                    unfullscreen.show_all ();
                    return true;
                }
                return false;
            });
            
            //positioning
            this.just_opened = true;int old_h=0, old_w=0;
            this.mainwindow.size_allocate.connect ( () => {
                if (this.mainwindow.get_allocated_width () != old_w || 
                    this.mainwindow.get_allocated_height () != old_h){
                    this.place ();
                    old_w = this.mainwindow.get_allocated_width  ();
                    old_h = this.mainwindow.get_allocated_height ();
                }
                return;
            });
            
            this.mainwindow.show_all ();
            
            /*moving the window by drag, fullscreen for dbl-click*/
            bool moving = false;
            this.canvas.button_press_event.connect ( (e) => {
                if (e.click_count > 1){
                    toggle_fullscreen ();
                    return true;
                }else{
                    moving = true;
                    return true;
                }
            });
            clutter.motion_notify_event.connect ( (e) => {
                if (moving){
                    moving = false;
                    this.mainwindow.begin_move_drag (1, 
                        (int)e.x_root, (int)e.y_root, e.time);
                    return true;
                }
                return false;
            });
            this.canvas.button_release_event.connect ( (e) => {
                moving = false;
                return false;
            });
            
            /*DnD*/
            Gtk.TargetEntry uris = {"text/uri-list", 0, 0};
            Gtk.drag_dest_set (this.mainwindow, 
                Gtk.DestDefaults.ALL, {uris}, Gdk.DragAction.MOVE);
            this.mainwindow.drag_data_received.connect ( (ctx, x, y, sel, info, time) => {
                for (var i=0;i<sel.get_uris ().length; i++)
                    this.tagview.add_play_item (sel.get_uris ()[i]);
                this.open_file (sel.get_uris ()[0]);
                this.toggle_play (true);
            });
        }
        
        private void toggle_play (bool start){
            Gst.State state;
            canvas.get_pipeline ().get_state (out state, null, 0);
            if (!start){
                toolbar.remove (this.pause);
                toolbar.insert (this.play, 0);
                play.show_all ();
                canvas.get_pipeline ().set_state (Gst.State.PAUSED);
                Source.remove (this.hiding_timer);
            }else{
                if (this.reached_end){
                    canvas.progress = 0.0;
                    this.reached_end = false;
                }
                canvas.get_pipeline ().set_state (Gst.State.PLAYING);
                toolbar.remove (this.play);
                toolbar.insert (this.pause, 0);
                pause.show_all ();
                this.place ();
                Source.remove (this.hiding_timer);
                this.hiding_timer = GLib.Timeout.add (2000, () => {
                    this.mainwindow.get_window ().set_cursor (blank_cursor);
                    float y2 = this.stage.height;
                    this.bar.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 1000, y:y2);
                    return false;
                });
            }
            this.place ();
        }
        
        private void toggle_fullscreen (){
            if (fullscreened){
                this.mainwindow.unmaximize ();
                this.mainwindow.unfullscreen ();
                this.fullscreened = false;
                this.toolbar.remove (this.unfullscreen);
            }else{
                this.mainwindow.fullscreen ();
                this.toolbar.insert (this.unfullscreen, 3);
                this.unfullscreen.show_all ();
                this.fullscreened = true;
            }
        }
        
        internal void open_file (string filename){
            var uri = File.new_for_commandline_arg (filename).get_uri ();
            canvas.uri = uri;
            canvas.audio_volume = 1.0;
            this.just_opened = true;
            previewer.uri = uri;
            previewer.audio_volume = 0.0;
            
            mainwindow.title = get_basename (uri);
            mainwindow.title = mainwindow.title.replace ("%20", " ").
                replace ("%5B", "[").replace ("%5D", "]").replace ("%7B", "{").
                replace ("%7D", "}").replace ("_", " ").replace ("."," ").replace ("  "," ");
            tagview.get_tags (uri, true);
            
            play.sensitive  = true;
            
            Timeout.add (100, () => {this.place ();return false;});
            
            this.toggle_play (true);
        }
        
        private void place (){
            this.tagview.height   = stage.height;
            this.tagview.x        = (this.tagview.expanded)?stage.width-this.tagview.width:stage.width;
            
            var tb_height = 56;
            this.bar.width  = stage.width;
            this.bar.y      = stage.height - tb_height;
            this.bar.height = tb_height;
            this.bar.x      = 0;
            toolbar.width_request = (int)this.bar.width;
            toolbar.height_request = tb_height;
            
            //aspect ratio handling
            if (this.just_opened && canvas.width == 0.0f){
                return;
            }else if (just_opened){
                canvas.get_base_size (out video_w, out video_h);
                this.just_opened = false;
            }
            if (stage.width > stage.height){
                this.canvas.height = stage.height;
                this.canvas.width  = stage.height / video_h * video_w;
                this.canvas.x      = (stage.width - this.canvas.width) / 2.0f;
                this.canvas.y      = 0.0f;
            }else{
                this.canvas.width  = stage.width;
                this.canvas.height = stage.width / video_w *  video_h;
                this.canvas.y      = (stage.height - this.canvas.height) / 2.0f;
                this.canvas.x      = 0.0f;
            }
        }
        
        //the application started
        public override void activate (){
            
        }
        
        //the application was requested to open some files
        public override void open (File [] files, string hint){
            for (var i=0;i<files.length;i++)
                this.tagview.add_play_item (files[i].get_path ());
            this.open_file (files[0].get_path ());
        }
    }
}

public static void main (string [] args){
    GtkClutter.init (ref args);
    ClutterGst.init (ref args);
    
    var app = new Audience.AudienceApp ();
    
    app.run (args);
}

