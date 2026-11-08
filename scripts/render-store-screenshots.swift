#!/usr/bin/env swift
// Render only real app captures. Missing inputs are errors; no placeholder UI is generated.
// Compile: xcrun swiftc -O scripts/render-store-screenshots.swift -o /tmp/runner-store-render
// Run: /tmp/runner-store-render --input /absolute/captures --output docs/release/screenshots
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Copy: Decodable {
  let schemaVersion: Int
  let width, height: Int
  let localizations: [String: Localization]
}
struct Localization: Decodable {
  let brand, sampleNote: String
  let screens: [Screen]
}
struct Screen: Decodable {
  let id, eyebrow, headline, subtitle: String
  let captures: [String]
  let captureLabels: [String]?
  let artwork: String
}
struct Failure: Error, CustomStringConvertible { let description: String }
func fail(_ message: String) throws -> Never { throw Failure(description: message) }
let fm = FileManager.default
let args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String, default fallback: String? = nil) -> String? {
  guard let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return fallback }
  return args[i + 1]
}
let root = URL(fileURLWithPath: option("--root", default: fm.currentDirectoryPath)!, isDirectory: true)
let copyURL = root.appendingPathComponent(option("--copy", default: "docs/release/screenshot-copy.json")!)
let output = URL(fileURLWithPath: option("--output", default: root.appendingPathComponent("docs/release/screenshots").path)!, isDirectory: true)
let yellow = NSColor(srgbRed: 215/255, green: 1, blue: 0, alpha: 1)
let black = NSColor(srgbRed: 9/255, green: 10/255, blue: 9/255, alpha: 1)
let cream = NSColor(srgbRed: 246/255, green: 244/255, blue: 236/255, alpha: 1)
let gray = NSColor(srgbRed: 184/255, green: 190/255, blue: 177/255, alpha: 1)

// AppKit's flipped coordinate system keeps layout values measured from the top.
func text(_ value: String, rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = cream, tracking: CGFloat = 0, minimum: CGFloat? = nil) throws {
  let paragraph = NSMutableParagraphStyle()
  paragraph.lineBreakMode = .byWordWrapping
  paragraph.lineSpacing = size * 0.04
  var selected = size
  while true {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: selected, weight: weight), .foregroundColor: color,
      .paragraphStyle: paragraph, .kern: tracking
    ]
    let item = NSAttributedString(string: value, attributes: attributes)
    let bounds = item.boundingRect(with: CGSize(width: rect.width, height: 10000),
      options: [.usesLineFragmentOrigin, .usesFontLeading])
    if bounds.height <= rect.height + 0.5 {
      item.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
      return
    }
    guard let floor = minimum, selected > floor else {
      try fail("Text does not fit: \(value) in \(rect)")
    }
    selected -= 1
  }
}
func headline(_ value: String) throws {
  let lines=value.components(separatedBy: "\n")
  guard lines.count == 2 else {try fail("Headlines must have exactly two designed lines")}
  var size:CGFloat=112
  while true {
    let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:size,weight:.heavy),.foregroundColor:cream,.kern:-4]
    if lines.allSatisfy({($0 as NSString).size(withAttributes:attributes).width <= 1170}) {
      for (index,line) in lines.enumerated() {
        (line as NSString).draw(at:CGPoint(x:72,y:218+CGFloat(index)*127),withAttributes:attributes)
      }
      return
    }
    size-=1
    if size < 86 {try fail("Headline line is too long: \(value)")}
  }
}
func stroke(_ points: [CGPoint], color: NSColor, width: CGFloat) {
  guard let first = points.first else { return }
  let p = NSBezierPath(); p.move(to: first)
  points.dropFirst().forEach { p.line(to: $0) }
  p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round
  color.setStroke(); p.stroke()
}
func trackPattern(_ width: CGFloat, _ height: CGFloat, seed: Int) {
  NSColor(srgbRed: 0.13, green: 0.16, blue: 0.09, alpha: 1).setStroke()
  for n in 0..<10 {
    let x = -610 + CGFloat(n) * 76 + CGFloat(seed % 3) * 20
    let p = NSBezierPath()
    p.move(to: CGPoint(x: x, y: height + 180))
    p.curve(to: CGPoint(x: width + 180, y: 660 + CGFloat(n) * 44),
      controlPoint1: CGPoint(x: x + 800, y: height - 200),
      controlPoint2: CGPoint(x: width - 180, y: 880 + CGFloat(n) * 44))
    p.lineWidth = 2; p.stroke()
  }
}
func scribble(_ y: CGFloat, _ width: CGFloat) {
  let p = NSBezierPath(); p.move(to: CGPoint(x: 79, y: y))
  p.curve(to: CGPoint(x: width, y: y - 6), controlPoint1: CGPoint(x: 300, y: y - 10),
    controlPoint2: CGPoint(x: width - 110, y: y + 12))
  p.lineWidth = 9; p.lineCapStyle = .round; yellow.setStroke(); p.stroke()
  stroke([CGPoint(x: 90,y:y+15),CGPoint(x:width-60,y:y+3)],color:yellow.withAlphaComponent(0.3),width:3)
}
func arrow(x: CGFloat, y: CGFloat, right: Bool) {
  let d: CGFloat = right ? 1 : -1
  let p = NSBezierPath(); p.move(to: CGPoint(x:x,y:y))
  let end = CGPoint(x: x + d * 94, y:y+104)
  p.curve(to:end,controlPoint1:CGPoint(x:x-d*25,y:y+84),controlPoint2:CGPoint(x:x+d*12,y:y+130))
  p.lineWidth=7; p.lineCapStyle = .round; yellow.setStroke();p.stroke()
  stroke([CGPoint(x:end.x-d*28,y:end.y-23),end,CGPoint(x:end.x-d*30,y:end.y+17)],color:yellow,width:7)
}
func sourceImage(_ url: URL) throws -> CGImage {
  guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),
        let image = CGImageSourceCreateImageAtIndex(source,0,nil) else {try fail("Cannot read capture: \(url.path)")}
  guard image.width >= 1000, image.height > image.width,
        (1.9...2.4).contains(Double(image.height)/Double(image.width)) else {
    try fail("Expected a full portrait iPhone capture, got \(image.width)x\(image.height): \(url.lastPathComponent)")
  }
  return image
}
func drawCapture(_ image: CGImage, x: CGFloat, y: CGFloat, width: CGFloat) -> CGRect {
  let height = width * CGFloat(image.height) / CGFloat(image.width)
  let rect=CGRect(x:x,y:y,width:width,height:height)
  // The outside frame is decoration; the app capture itself is never reconstructed or stretched.
  NSColor(srgbRed:0.23,green:0.25,blue:0.20,alpha:1).setFill()
  NSBezierPath(roundedRect:rect.insetBy(dx:-7,dy:-7),xRadius:50,yRadius:50).fill()
  NSGraphicsContext.saveGraphicsState()
  NSBezierPath(roundedRect:rect,xRadius:44,yRadius:44).addClip()
  NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)).draw(in:rect,from:.zero,
    operation:.copy,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
  NSGraphicsContext.restoreGraphicsState()
  return rect
}
func artwork(_ name: String, rect: CGRect, opacity: CGFloat = 1) {
  let path=root.appendingPathComponent("Runner: Analyzer & Tracking/OnboardingAssets.xcassets/Onboarding\(name).imageset/Artwork.png")
  guard let image=NSImage(contentsOf:path) else {return}
  image.draw(in:rect,from:.zero,operation:.sourceOver,fraction:opacity,respectFlipped:true,hints:nil)
}
func render(_ screen: Screen, locale: String, copy: Localization, input: URL, width:Int,height:Int,index:Int) throws {
  let captures = try screen.captures.map { try sourceImage(input.appendingPathComponent("\(locale)-\($0).png")) }
  guard captures.count == 1 || captures.count == 2 else {try fail("Expected one or two captures")}
  guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,
    bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,
    bytesPerRow:width*4,bitsPerPixel:32), let context=NSGraphicsContext(bitmapImageRep:bitmap) else {
    try fail("Unable to create opaque output buffer")
  }
  NSGraphicsContext.saveGraphicsState();defer{NSGraphicsContext.restoreGraphicsState()}
  NSGraphicsContext.current=context
  let transform=NSAffineTransform();transform.translateX(by:0,yBy:CGFloat(height));transform.scaleX(by:1,yBy:-1);transform.concat()
  let flipped=NSGraphicsContext(cgContext:context.cgContext,flipped:true);NSGraphicsContext.current=flipped
  black.setFill();CGRect(x:0,y:0,width:width,height:height).fill()
  // Keep one design coordinate system across Apple's large and medium slots.
  // Uniform scaling avoids stretching either the artwork or genuine app captures.
  let designScale = min(CGFloat(width) / 1320, CGFloat(height) / 2868)
  let designTransform = NSAffineTransform()
  designTransform.translateX(by:(CGFloat(width) - 1320 * designScale) / 2,
    yBy:(CGFloat(height) - 2868 * designScale) / 2)
  designTransform.scale(by:designScale);designTransform.concat()
  trackPattern(1320,2868,seed:index)
  try text(copy.brand,rect:CGRect(x:76,y:58,width:700,height:60),size:43,weight:.black,color:yellow,tracking:5)
  try text(String(format:"%02d / 08",index),rect:CGRect(x:1080,y:69,width:170,height:40),size:25,weight:.semibold,color:gray,tracking:2)
  try text(screen.eyebrow,rect:CGRect(x:78,y:160,width:1160,height:48),size:25,weight:.bold,color:yellow,tracking:2,minimum:21)
  try headline(screen.headline)
  scribble(496,CGFloat(min(1060,530+screen.headline.count*6)))
  try text(screen.subtitle,rect:CGRect(x:78,y:538,width:1120,height:100),size:36,weight:.medium,color:gray,minimum:32)
  if captures.count == 1 {
    let h:CGFloat=2060
    let w=min(960,h*CGFloat(captures[0].width)/CGFloat(captures[0].height))
    let rect=drawCapture(captures[0],x:(1320-w)/2,y:654,width:w)
    arrow(x:51,y:802,right:true)
    // A small illustration stays beyond the capture and never obscures app content.
    artwork(screen.artwork,rect:CGRect(x:1160,y:2470,width:145,height:145))
    stroke([CGPoint(x:rect.maxX+18,y:1900),CGPoint(x:rect.maxX+46,y:1855)],color:yellow,width:5)
  } else {
    let a=drawCapture(captures[0],x:60,y:680,width:558)
    let b=drawCapture(captures[1],x:702,y:1095,width:558)
    let labels=screen.captureLabels ?? ["", ""]
    try text(labels[0],rect:CGRect(x:65,y:a.maxY+32,width:550,height:90),size:27,weight:.bold,color:yellow,tracking:1,minimum:23)
    try text(labels[1],rect:CGRect(x:706,y:b.maxY+32,width:550,height:90),size:27,weight:.bold,color:yellow,tracking:1,minimum:23)
    artwork(screen.artwork,rect:CGRect(x:755,y:652,width:380,height:380))
    arrow(x:645,y:930,right:true)
    stroke([CGPoint(x:124,y:2240),CGPoint(x:157,y:2202),CGPoint(x:178,y:2217),CGPoint(x:235,y:2138)],color:yellow,width:9)
    let phrase = locale == "de" ? "DEIN TEMPO.\nDEIN WEG." : "YOUR PACE.\nYOUR WAY."
    try text(phrase,rect:CGRect(x:78,y:2368,width:490,height:180),size:58,weight:.black,color:cream,tracking:-1)
  }
  try text(copy.sampleNote,rect:CGRect(x:78,y:2792,width:1160,height:45),size:24,weight:.medium,color:gray,tracking:0.5)
  let directory=output.appendingPathComponent(locale,isDirectory:true);try fm.createDirectory(at:directory,withIntermediateDirectories:true)
  let url=directory.appendingPathComponent(screen.id+".png")
  // Strip the alpha channel instead of merely filling it: App Store Connect rejects RGBA PNGs.
  guard let opaque=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,
    bitsPerSample:8,samplesPerPixel:3,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceRGB,
    bytesPerRow:width*3,bitsPerPixel:24), let source=bitmap.bitmapData, let destination=opaque.bitmapData
  else {try fail("Unable to flatten output")}
  for y in 0..<height {
    for x in 0..<width {
      let from=y*bitmap.bytesPerRow+x*4, to=y*opaque.bytesPerRow+x*3
      destination[to]=source[from];destination[to+1]=source[from+1];destination[to+2]=source[from+2]
    }
  }
  guard let png=opaque.representation(using:.png,properties:[:]) else {try fail("PNG encoding failed")}
  try png.write(to:url,options:.atomic)
  guard let check=CGImageSourceCreateWithURL(url as CFURL,nil),
    let properties=CGImageSourceCopyPropertiesAtIndex(check,0,nil) as? [CFString:Any],
    properties[kCGImagePropertyPixelWidth] as? Int == width,
    properties[kCGImagePropertyPixelHeight] as? Int == height,
    (properties[kCGImagePropertyHasAlpha] as? Bool ?? false) == false else {try fail("Export verification failed: \(url.path)")}
  print("Rendered \(locale)/\(screen.id).png · \(width)×\(height), opaque")
}
do {
  guard let inputPath=option("--input") else {try fail("Usage: render-store-screenshots --input CAPTURE_FOLDER [--output OUTPUT_FOLDER] [--root REPO_ROOT] [--language en|de] [--only 01-overview] [--validate-only]")}
  let input=URL(fileURLWithPath:inputPath,isDirectory:true)
  let copy=try JSONDecoder().decode(Copy.self,from:Data(contentsOf:copyURL))
  guard copy.schemaVersion == 1, copy.width == 1320, copy.height == 2868 else {try fail("Unsupported output specification")}
  let display = option("--display", default:"large")!
  guard ["large","medium"].contains(display) else {try fail("Display must be large or medium")}
  let exportWidth = display == "medium" ? 1206 : copy.width
  let exportHeight = display == "medium" ? 2622 : copy.height
  let languages=option("--language").map{[$0]} ?? ["en","de"]
  var missing:[String]=[]
  for language in languages {
    guard let localized=copy.localizations[language] else {try fail("Unsupported language: \(language)")}
    guard localized.screens.count == 8 else {try fail("Each language requires exactly eight screens")}
    if let selected=option("--only"), !localized.screens.contains(where:{$0.id == selected}) {
      try fail("Unknown screenshot: \(selected)")
    }
    for screen in localized.screens where option("--only") == nil || screen.id == option("--only") {
      guard (1...2).contains(screen.captures.count) else {try fail("Expected one or two captures: \(screen.id)")}
      if screen.captures.count == 2, screen.captureLabels?.count != 2 {
        try fail("Paired captures need two labels: \(screen.id)")
      }
      for key in screen.captures {
        let path=input.appendingPathComponent("\(language)-\(key).png")
        if !fm.fileExists(atPath:path.path){missing.append(path.path)}else{_=try sourceImage(path)}
      }
    }
  }
  guard missing.isEmpty else {try fail("Missing genuine app captures:\n"+missing.joined(separator:"\n"))}
  if args.contains("--validate-only") {print("All required genuine captures are present and correctly shaped.");exit(0)}
  for language in languages {
    let localized=copy.localizations[language]!
    for (index,screen) in localized.screens.enumerated() where option("--only") == nil || screen.id == option("--only") {
      try render(screen,locale:language,copy:localized,input:input,width:exportWidth,height:exportHeight,index:index+1)
    }
  }
} catch {fputs("\(error)\n",stderr);exit(1)}
