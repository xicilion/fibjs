var test = require("test");
test.setup();

var test_util = require("./test_util");

var fs = require("fs");
var path = require("path");

var win = process.platform === "win32";
var darwin = process.platform === "darwin";

var htmlDir = path.resolve(__dirname, './gui_files/html');
var html = fs.readTextFile(path.resolve(htmlDir, './basic-loop.html'));

if (win || darwin) {
  var http = require("http");
  var gui = require("gui");
  var coroutine = require("coroutine");

  var base_port = coroutine.vmid * 10000;

  describe("gui", () => {
    after(test_util.cleanup);

    var check = false;

    before(() => {
      var svr = new http.Server(8999 + base_port, {
        '/': r => {
          check = true;
          r.response.write(html);
        },
        '/(.+)\.html': http.fileHandler(htmlDir)
      });
      svr.start();
      test_util.push(svr.socket);
    });

    describe("webview", () => {
      after(test_util.cleanup);

      it("basic", () => {
        var closed = false;
        var events = {};
        var win = gui.open("http://127.0.0.1:" + (8999 + base_port) + "/");

        var cnt = 0;

        win.onmessage = m => {
          cnt++;

          if (m === "try close") {
            win.close();
          } else {
            win.close();
          }
        };

        win.onclosed = () => {
          closed = true;
          win = undefined;
        };

        win.onload = () => {
          win.postMessage("hello");
        };

        // In Dardinw, WebView would auto-centralize its window by default, it trigger once emit("move")
        win.onmove = () => {
          if (darwin) events.onmove = true;
        }

        for (var i = 0; i < 1000 && !check; i++) coroutine.sleep(10);

        assert.ok(check);

        for (var i = 0; i < 1000 && test_util.countObject("WebView"); i++)
          test_util.gc();

        assert.equal(test_util.countObject("WebView"), 0);
        assert.equal(closed, true);
        assert.equal(cnt, 2);

        assert.isTrue(events.onmove)
      });
    });

    describe.only("close", () => {
      it("close directly by default", () => {
        var win = gui.open("http://127.0.0.1:" + (8999 + base_port) + "/close-directly.html");

        win.close();
      });
    });

    darwin && describe.only("resize", () => {
      var events_resize = {};

      it("resiable", () => {
        var win = gui.open("http://127.0.0.1:" + (8999 + base_port) + "/resizable.html", {
          title: "Resizable"
        });

        var MAX_RESIZE_CNT = 5;
        var resize_cnt = 0;

        win.onload = () => {
          console.log('window onload');
        }

        win.on('resizestart', () => {
          console.log('window onresizestart');
        })

        win.on('resizeend', () => {
          console.log('window onresizeend');
          // if (++resize_cnt >= MAX_RESIZE_CNT)
          win.close()
          win = undefined
        });

        win.onresize = (evt) => {
          events_resize.onresize = true;
          console.log('window onresize, w: %s', evt.width);

          events_resize.onresize_width_ok = evt.hasOwnProperty('width');
          events_resize.onresize_height_ok = evt.hasOwnProperty('height');
        }

        for (var i = 0; i < 1000 && test_util.countObject("WebView"); i++)
          test_util.gc();

        assert.isTrue(events_resize.onresize)
        assert.isTrue(events_resize.onresize_width_ok)
        assert.isTrue(events_resize.onresize_height_ok)
      });
    });

    it("log", () => {
      var p = process.open(process.execPath, [
        path.join(__dirname, "gui_files", "gui1.js")
      ]);
      var r = p.stdout.readLines();
      assert.equal(r[0], "this is.a log");
      assert.equal(r[1], "this is.a warn");
      assert.ok(r[2].startsWith("WebView Error:"));
    });

    it("debug", () => {
      var p = process.open(process.execPath, [
        path.join(__dirname, "gui_files", "gui2.js")
      ]);
      var r = p.stdout.readLines();
      assert.equal(r.length, 0);
    });
  });
}

require.main === module && test.run(console.DEBUG);
