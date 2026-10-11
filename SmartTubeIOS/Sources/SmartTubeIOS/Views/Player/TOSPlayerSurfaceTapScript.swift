/// Installed only in the iOS TOS player. Handle video-surface taps in the frame
/// that owns the video, before YouTube's tap-to-toggle-playback handler runs.
enum TOSPlayerSurfaceTapScript {
    static let source = """
        (function() {
            var touchStart = null;
            var tapSlop = 10;

            function surfacePlayer(target) {
                var player = document.getElementById('movie_player');
                if (!player || !target || !target.matches) return null;
                // Exact surface targets only: never swallow buttons, the scrubber,
                // menus, links, error overlays, or the initial/replay play button.
                if (target !== player && !target.matches('video.html5-main-video, .html5-video-container')) return null;
                if (!player.contains(target)) return null;
                var video = player.querySelector('video');
                if (!video || video.readyState < 2 || video.ended) return null;
                // Leave system fullscreen and unfamiliar player variants alone.
                if (document.fullscreenElement === video) return null;
                if (typeof player.showControls !== 'function' || typeof player.hideControls !== 'function') return null;
                return player;
            }

            function toggleControls(event, player) {
                event.preventDefault();
                event.stopImmediatePropagation();
                var visible = player.classList.contains('ytp-autohide');
                if (visible) player.showControls();
                else player.hideControls();
                var callback = window.__nativeYTCallback;
                if (callback) callback.postMessage(JSON.stringify({type: 'surfaceTap', controlsVisible: visible}));
            }

            // Do not cancel touchstart/move: UIKit must still receive swipe
            // navigation and brightness/volume drags. Track maximum displacement,
            // so a drag that returns to its starting point is not mistaken for a tap.
            document.addEventListener('touchstart', function(event) {
                touchStart = null;
                if (event.touches.length !== 1 || !surfacePlayer(event.target)) return;
                var touch = event.touches[0];
                touchStart = {id: touch.identifier, x: touch.clientX, y: touch.clientY};
            }, {capture: true, passive: true});

            document.addEventListener('touchmove', function(event) {
                if (!touchStart) return;
                if (event.touches.length !== 1) { touchStart = null; return; }
                var touch = event.touches[0];
                if (touch.identifier !== touchStart.id ||
                    Math.abs(touch.clientX - touchStart.x) > tapSlop ||
                    Math.abs(touch.clientY - touchStart.y) > tapSlop) touchStart = null;
            }, {capture: true, passive: true});

            document.addEventListener('touchcancel', function() { touchStart = null; }, true);
            document.addEventListener('touchend', function(event) {
                var start = touchStart;
                touchStart = null;
                if (!start || event.touches.length !== 0 || event.changedTouches.length !== 1) return;
                var touch = event.changedTouches[0];
                if (touch.identifier !== start.id ||
                    Math.abs(touch.clientX - start.x) > tapSlop ||
                    Math.abs(touch.clientY - start.y) > tapSlop) return;
                var player = surfacePlayer(event.target);
                // Cancelling touchend also suppresses the synthesized mouse click,
                // so one physical tap toggles the controls exactly once.
                if (player && event.cancelable) toggleControls(event, player);
            }, {capture: true, passive: false});

            // Pointer/trackpad clicks and accessibility activation without a touch.
            document.addEventListener('click', function(event) {
                if (event.button !== 0) return;
                var player = surfacePlayer(event.target);
                if (player) toggleControls(event, player);
            }, true);
        })();
        """
}
