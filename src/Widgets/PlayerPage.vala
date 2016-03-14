namespace Audience {
    private  const string[] SUBTITLE_EXTENSIONS = {
        "sub",
        "srt",
        "smi",
        "ssa",
        "ass",
        "asc"
    };

    public class PlayerPage : Gtk.EventBox {
        public signal void unfullscreen_clicked ();
        public signal void ended ();

        public GtkClutter.Embed clutter;
        private Clutter.Actor video_actor;
        private Audience.Widgets.BottomBar bottom_bar;
        private Clutter.Stage stage;
        private Gtk.Revealer unfullscreen_bar;
        private GtkClutter.Actor unfullscreen_actor;
        private GtkClutter.Actor bottom_actor;
        private GnomeMediaKeys mediakeys;
        private ClutterGst.Playback playback;

        public GnomeSessionManager session_manager;
        uint32 inhibit_cookie;

        private bool mouse_primary_down = false;

        public bool repeat {
            get{
                return bottom_bar.get_repeat ();
            }

            set{
                bottom_bar.set_repeat (value);
            }
        }

        public bool playing {
            get {
                return playback.playing;
            }
            set {
                if (playback.playing == value)
                    return;

                playback.playing = value;
            }
        }

        private bool _fullscreened = false;
        public bool fullscreened {
            get {
                return _fullscreened;
            }
            set {
                _fullscreened = value;
                bottom_bar.fullscreen = value;
            }
        }

        public PlayerPage () {
            playback = new ClutterGst.Playback ();
            playback.set_seek_flags (ClutterGst.SeekFlags.ACCURATE);
            playback.notify["playing"].connect (() => {
                inhibit_session (playback.playing);
            });

            clutter = new GtkClutter.Embed ();
            clutter.use_layout_size = true;
            stage = (Clutter.Stage)clutter.get_stage ();
            stage.background_color = {0, 0, 0, 0};

            video_actor = new Clutter.Actor ();
            var aspect_ratio = ClutterGst.Aspectratio.@new ();
            ((ClutterGst.Content) aspect_ratio).player = playback;
            video_actor.content = aspect_ratio;

            video_actor.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.WIDTH, 0));
            video_actor.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.HEIGHT, 0));

            stage.add_child (video_actor);

            bottom_bar = new Widgets.BottomBar (playback);
            bottom_bar.bind_property ("playing", playback, "playing", BindingFlags.BIDIRECTIONAL);
            bottom_bar.unfullscreen.connect (() => unfullscreen_clicked ());

            unfullscreen_bar = bottom_bar.get_unfullscreen_button ();

            bottom_actor = new GtkClutter.Actor.with_contents (bottom_bar);
            bottom_actor.opacity = GLOBAL_OPACITY;
            bottom_actor.add_constraint (new Clutter.BindConstraint (stage, Clutter.BindCoordinate.WIDTH, 0));
            bottom_actor.add_constraint (new Clutter.AlignConstraint (stage, Clutter.AlignAxis.Y_AXIS, 1));
            stage.add_child (bottom_actor);

            unfullscreen_actor = new GtkClutter.Actor.with_contents (unfullscreen_bar);
            unfullscreen_actor.opacity = GLOBAL_OPACITY;
            unfullscreen_actor.add_constraint (new Clutter.AlignConstraint (stage, Clutter.AlignAxis.X_AXIS, 1));
            unfullscreen_actor.add_constraint (new Clutter.AlignConstraint (stage, Clutter.AlignAxis.Y_AXIS, 0));
            stage.add_child (unfullscreen_actor);

            //media keys
            try {
                mediakeys = Bus.get_proxy_sync (BusType.SESSION,
                    "org.gnome.SettingsDaemon", "/org/gnome/SettingsDaemon/MediaKeys");
                mediakeys.MediaPlayerKeyPressed.connect ((bus, app, key) => {
                    if (app != "audience")
                       return;
                    switch (key) {
                        case "Previous":
                            get_playlist_widget ().previous ();
                            break;
                        case "Next":
                            get_playlist_widget ().next ();
                            break;
                        case "Play":
                            playback.playing = !playback.playing;
                            break;
                        default:
                            break;
                    }
                });

                mediakeys.GrabMediaPlayerKeys("audience", 0);
            } catch (Error e) {
                warning (e.message);
            }

            App.get_instance ().mainwindow.motion_notify_event.connect ((event) => {
                if (mouse_primary_down && settings.move_window) {
                    mouse_primary_down = false;
                    App.get_instance ().mainwindow.begin_move_drag (Gdk.BUTTON_PRIMARY,
                        (int)event.x_root, (int)event.y_root, event.time);
                }

                Gtk.Allocation allocation;
                clutter.get_allocation (out allocation);
                return update_pointer_position (event.y, allocation.height);
            });

            this.button_press_event.connect ((event) => {
                if (event.button == Gdk.BUTTON_PRIMARY)
                    mouse_primary_down = true;

                return false;
            });

            this.button_release_event.connect ((event) => {
                if (event.button == Gdk.BUTTON_PRIMARY)
                    mouse_primary_down = false;

                return false;
            });

            this.leave_notify_event.connect ((event) => {
                Gtk.Allocation allocation;
                clutter.get_allocation (out allocation);

                if (event.x == event.window.get_width ())
                    return update_pointer_position (event.window.get_height (), allocation.height);
                else if (event.x == 0)
                    return update_pointer_position (event.window.get_height (), allocation.height);

                return update_pointer_position (event.y, allocation.height);
            });

            this.destroy.connect (() => {
                // FIXME:should find better way to decide if its end of playlist
                if (playback.progress > 0.99)
                    settings.last_stopped = 0;
                else
                    settings.last_stopped = playback.progress;

                get_playlist_widget ().save_playlist ();
            });

            //end
            playback.eos.connect (() => {
                Idle.add (() => {
                    playback.progress = 0;
                    if (!get_playlist_widget ().next ()) {
                        if (repeat) {
                            play_file (get_playlist_widget ().get_first_item ().get_uri ());
                            playback.playing = true;
                        } else {
                            playback.playing = false;
                            settings.last_stopped = 0;
                            ended ();
                        }
                    }
                    return false;
                });
            });

            //playlist wants us to open a file
            get_playlist_widget ().play.connect ((file) => {
                this.play_file (file.get_uri ());
            });

            bottom_bar.notify["child-revealed"].connect (() => {
                if (bottom_bar.child_revealed == true) {
                    App.get_instance ().mainwindow.get_window ().set_cursor (null);
                } else {
                    var window = App.get_instance ().mainwindow.get_window ();
                    var display = window.get_display ();
                    var cursor = new Gdk.Cursor.for_display (display, Gdk.CursorType.BLANK_CURSOR);
                    window.set_cursor (cursor);
                }
            });

            add (clutter);
            show_all ();
        }

        public void play_file (string uri, bool from_beginning = true) {
            debug ("Opening %s", uri);
            playback.uri = uri;
            get_playlist_widget ().set_current (uri);
            bottom_bar.set_preview_uri (uri);

            string? sub_uri = get_subtitle_for_uri (uri);
            if (sub_uri != null)
                playback.set_subtitle_uri (sub_uri);

            App.get_instance ().mainwindow.title = get_title (uri);

            playback.playing = !settings.playback_wait;
            if (from_beginning) {
                playback.progress = 0.0;
            } else {
                playback.progress = settings.last_stopped;
            }

            Gtk.RecentManager recent_manager = Gtk.RecentManager.get_default ();
            recent_manager.add_item (uri);

            /*subtitles/audio tracks*/
            bottom_bar.preferences_popover.setup_text ();
            bottom_bar.preferences_popover.setup_audio ();
        }

        public void next () {
            get_playlist_widget ().next ();
        }

        public void prev () {
            get_playlist_widget ().next ();
        }

        public void resume_last_videos () {
            play_file (settings.current_video);
            playback.playing = false;
            if (settings.resume_videos) {
                playback.progress = settings.last_stopped;
            } else {
                playback.progress = 0.0;
            }

            playback.playing = !settings.playback_wait;
        }

        public void append_to_playlist (File file) {
            if (playback.playing && is_subtitle (file.get_uri ())) {
                playback.set_subtitle_uri (file.get_uri ());
            } else {
                get_playlist_widget ().add_item (file);
            }
        }

        public void play_first_in_playlist () {
            var file = get_playlist_widget ().get_first_item ();
            play_file (file.get_uri ());
        }

        public void reveal_control () {
            bottom_bar.reveal_control ();
        }

        public void next_audio () {
            bottom_bar.preferences_popover.next_audio ();
        }

        public void next_text () {
            bottom_bar.preferences_popover.next_text ();
        }

        public void seek_jump_seconds (int seconds) {
            var duration = playback.duration;
            var progress = playback.progress;
            var new_progress = ((duration * progress) + (double)seconds)/duration;
            playback.progress = double.min (new_progress, 1.0);
        }

        private Widgets.Playlist get_playlist_widget () {
            return bottom_bar.playlist_popover.playlist;
        }

        private string? get_subtitle_for_uri (string uri) {
            string without_ext;
            int last_dot = uri.last_index_of (".", 0);
            int last_slash = uri.last_index_of ("/", 0);

            if (last_dot < last_slash) //we dont have extension
                without_ext = uri;
            else
                without_ext = uri.slice (0, last_dot);

            foreach (string ext in SUBTITLE_EXTENSIONS){
                string sub_uri = without_ext + "." + ext;
                if (File.new_for_uri (sub_uri).query_exists ())
                    return sub_uri;
            }
            return null;
        }

        private bool is_subtitle (string uri) {
            if (uri.length < 4 || uri.get_char (uri.length-4) != '.')
                return false;

            foreach (string ext in SUBTITLE_EXTENSIONS) {
                if (uri.down ().has_suffix (ext))
                    return true;
            }

            return false;
        }

        public bool update_pointer_position (double y, int window_height) {
            App.get_instance ().mainwindow.get_window ().set_cursor (null);

            bottom_bar.reveal_control ();

            return false;
        }

        X.Display dpy;
        int timeout = -1;
        int interval;
        int prefer_blanking;
        int allow_exposures;
        void inhibit_session (bool inhibit) {
            debug ("set inhibit to " + (inhibit ? "true" : "false"));
            //TODO: Remove X Dependency!
            //store the default values for setting back

            if (dpy == null)
                dpy = new X.Display ();

            if (timeout == -1)
                dpy.get_screensaver (out timeout, out interval, out prefer_blanking, out allow_exposures);

            dpy.set_screensaver (inhibit ? 0 : timeout, interval, prefer_blanking, allow_exposures);

            //prevent screenlocking in Gnome 3 using org.gnome.SessionManager
            try {
                session_manager = Bus.get_proxy_sync (BusType.SESSION,
                        "org.gnome.SessionManager", "/org/gnome/SessionManager");
                if (inhibit) {
                    inhibit_cookie = session_manager.Inhibit ("audience", 0, "Playing Video using Audience", 12);
                } else {
                    session_manager.Uninhibit (inhibit_cookie);
                }
            } catch (Error e) {
                warning (e.message);
            }
        }
    }
}
