import AppKit
let image = NSImage(size: NSSize(width:620,height:380))
image.lockFocus()
NSColor(calibratedRed:0.94,green:0.97,blue:1,alpha:1).setFill(); NSRect(x:0,y:0,width:620,height:380).fill()
func text(_ s:String,_ x:Double,_ y:Double,_ size:Double,_ color:NSColor) { (s as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:.medium),.foregroundColor:color]) }
text("Pstryk",255,320,30,.systemBlue)
text("→",280,195,52,.systemBlue)
text("Przeciągnij Pstryk do Aplikacji",167,110,19,.darkGray)
image.unlockFocus()
let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
