import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // 最初は 1200x800 で画面の中央に。コート全体と操作説明が収まる大きさより小さくはしない
    self.setContentSize(NSSize(width: 1200, height: 800))
    self.contentMinSize = NSSize(width: 980, height: 680)
    self.title = "PONG!"
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
