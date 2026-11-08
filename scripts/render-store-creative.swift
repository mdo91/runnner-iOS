#!/usr/bin/env swift
// App Store creative layouts: original illustration plus unchanged, genuine app captures.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("docs/release/creative-assets")
let captures = output.appendingPathComponent("sources")
let black = NSColor(srgbRed: 0.035, green: 0.039, blue: 0.035, alpha: 1)
let yellow = NSColor(srgbRed: 215/255, green: 1, blue: 0, alpha: 1)
let cream = NSColor(srgbRed: 246/255, green: 244/255, blue: 236/255, alpha: 1)
func image(_ path: URL) -> NSImage {
  guard let value = NSImage(contentsOf: path) else { fatalError("Missing input: \(path.path)") }
  return value
}
func fit(_ image: NSImage, in box: CGRect) {
  let scale = min(box.width / image.size.width, box.height / image.size.height)
  let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
  image.draw(in: CGRect(x: box.midX-size.width/2, y: box.midY-size.height/2, width: size.width, height: size.height),
    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
}
func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = cream, weight: NSFont.Weight = .heavy) {
  (value as NSString).draw(at: CGPoint(x:x,y:y), withAttributes: [
    .font: NSFont.systemFont(ofSize:size,weight:weight), .foregroundColor:color, .kern:-size*0.025])
}
func render(_ name: String, width: Int, height: Int, draw: () -> Void) throws {
  let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:width*4,bitsPerPixel:32)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
  let transform=NSAffineTransform(); transform.translateX(by:0,yBy:CGFloat(height)); transform.scaleX(by:1,yBy:-1); transform.concat()
  NSGraphicsContext.current = NSGraphicsContext(cgContext:NSGraphicsContext.current!.cgContext,flipped:true)
  black.setFill(); CGRect(x:0,y:0,width:width,height:height).fill()
  draw()
  NSGraphicsContext.restoreGraphicsState()
  let opaque = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:3,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:width*3,bitsPerPixel:24)!
  let source=bitmap.bitmapData!, destination=opaque.bitmapData!
  for y in 0..<height { for x in 0..<width {
    let a=y*bitmap.bytesPerRow+x*4, b=y*opaque.bytesPerRow+x*3
    destination[b]=source[a]; destination[b+1]=source[a+1]; destination[b+2]=source[a+2]
  }}
  let file=output.appendingPathComponent(name)
  try opaque.representation(using:.png,properties:[:])!.write(to:file,options:.atomic)
  let check=CGImageSourceCreateWithURL(file as CFURL,nil)!
  let properties=CGImageSourceCopyPropertiesAtIndex(check,0,nil)! as NSDictionary
  precondition(properties[kCGImagePropertyPixelWidth] as! Int == width)
  precondition(properties[kCGImagePropertyPixelHeight] as! Int == height)
  precondition(!(properties[kCGImagePropertyHasAlpha] as? Bool ?? false))
  print("\(name): \(width)×\(height), opaque RGB")
}
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let hero = image(output.appendingPathComponent("header-source.png"))
try render("header.png",width:3840,height:1646) {
  // Preserve the complete illustration and its aspect ratio within Apple's exact export size.
  fit(hero,in:CGRect(x:0,y:0,width:3840,height:1646))
}
let runner=image(root.appendingPathComponent("Runner: Analyzer & Tracking/OnboardingAssets.xcassets/OnboardingWelcome.imageset/Artwork.png"))
for locale in ["en","de"] {
  let screen=image(captures.appendingPathComponent("\(locale)-01-overview.png"))
  try render("search-\(locale).png",width:1920,height:1280) {
    // Sparse track lines frame the composition, with all copy inside the central safe region.
    for i in 0..<4 {
      let line=NSBezierPath(ovalIn:CGRect(x:-450+CGFloat(i)*62,y:850+CGFloat(i)*38,width:2100,height:620))
      NSColor(white:0.12,alpha:1).setStroke(); line.lineWidth=3; line.stroke()
    }
    text("RUNNER",x:150,y:132,size:44,color:yellow,weight:.bold)
    text(locale == "de" ? "Jeder Lauf." : "Every run.",x:148,y:235,size:100)
    text(locale == "de" ? "Im Blick." : "Understood.",x:148,y:347,size:100,color:yellow)
    text(locale == "de" ? "Tempo. Puls. Fortschritt." : "Pace. Heart rate. Progress.",x:153,y:485,size:36,weight:.medium)
    fit(runner,in:CGRect(x:240,y:625,width:480,height:495))
    // No invented UI or retouching: fit the full simulator capture into a simple rounded card.
    let card=CGRect(x:1100,y:105,width:493,height:1070)
    let frame=NSBezierPath(roundedRect:card.insetBy(dx:-7,dy:-7),xRadius:54,yRadius:54)
    NSColor(white:0.24,alpha:1).setFill(); frame.fill()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect:card,xRadius:48,yRadius:48).addClip()
    fit(screen,in:card)
    NSGraphicsContext.restoreGraphicsState()
    let arrow=NSBezierPath(); arrow.move(to:CGPoint(x:790,y:670)); arrow.curve(to:CGPoint(x:1030,y:590),controlPoint1:CGPoint(x:870,y:700),controlPoint2:CGPoint(x:950,y:600))
    arrow.move(to:CGPoint(x:990,y:587)); arrow.line(to:CGPoint(x:1030,y:590)); arrow.line(to:CGPoint(x:1009,y:625))
    yellow.setStroke(); arrow.lineWidth=7; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
  }
}
