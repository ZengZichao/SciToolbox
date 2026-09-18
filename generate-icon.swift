#!/usr/bin/env swift
// SciToolbox App Icon Generator
// Design: gradient squircle + white flask (science motif) with atom
// Output: AppIcon_1024.png

import AppKit
import CoreGraphics
import Foundation

let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: Int(S), height: Int(S),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create CGContext\n", stderr)
    exit(1)
}

// MARK: 1. Background squircle with gradient

let inset: CGFloat = S * 0.05
let bgRect = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let cornerR: CGFloat = S * 0.2237  // macOS squircle ratio
let squircle = CGPath(roundedRect: bgRect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)

ctx.addPath(squircle)
ctx.clip()

// Linear gradient: top-left teal → bottom-right deeper blue (clean blue, no purple)
let grad = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 0.13, green: 0.58, blue: 0.85, alpha: 1),  // #2196D9 (teal-blue)
        CGColor(red: 0.10, green: 0.46, blue: 0.82, alpha: 1),  // #1976D2 (clean blue)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: 0, y: S),
                       end: CGPoint(x: S, y: 0),
                       options: [])

// Subtle inner highlight (top-left glow)
let highlight = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0),
    ] as CFArray,
    locations: [0, 0.45]
)!
ctx.drawLinearGradient(highlight,
                       start: CGPoint(x: S * 0.15, y: S * 0.95),
                       end: CGPoint(x: S * 0.5, y: S * 0.35),
                       options: [])

// MARK: 2. Flask (Erlenmeyer conical flask)

let cx: CGFloat = S * 0.5  // center X
let flaskTop: CGFloat = S * 0.32  // top of flask neck
let flaskBottom: CGFloat = S * 0.72  // bottom of flask body

// Flask neck (narrow rectangle at top)
let neckWidth: CGFloat = S * 0.085
let neckHeight: CGFloat = S * 0.14
let neckLeft = cx - neckWidth / 2
let neckRight = cx + neckWidth / 2
let neckBottom = flaskTop + neckHeight
let bodyTop = neckBottom  // where neck meets body

// Flask body (triangle/cone shape widening downward)
let bodyHalfWidth: CGFloat = S * 0.165
let bodyLeft = cx - bodyHalfWidth
let bodyRight = cx + bodyHalfWidth
let bodyBottom = flaskBottom

// Draw flask outline (neck + conical body) as a single path
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Neck outline: left side
let neckLineW: CGFloat = S * 0.022
ctx.setLineWidth(neckLineW)

// Left neck line
ctx.move(to: CGPoint(x: neckLeft, y: flaskTop))
ctx.addLine(to: CGPoint(x: neckLeft, y: neckBottom))
// Left cone line (neck to body edge)
ctx.addLine(to: CGPoint(x: bodyLeft, y: bodyBottom))
// Bottom line
ctx.addLine(to: CGPoint(x: bodyRight, y: bodyBottom))
// Right cone line (body edge to neck)
ctx.addLine(to: CGPoint(x: neckRight, y: neckBottom))
// Right neck line
ctx.addLine(to: CGPoint(x: neckRight, y: flaskTop))
ctx.strokePath()

// Flask rim (horizontal line at top of neck)
let rimW: CGFloat = S * 0.025
ctx.setLineWidth(rimW)
ctx.move(to: CGPoint(x: neckLeft - S * 0.015, y: flaskTop))
ctx.addLine(to: CGPoint(x: neckRight + S * 0.015, y: flaskTop))
ctx.strokePath()

// MARK: 3. Liquid inside flask (filled triangle with curved top)

ctx.saveGState()

// Clip to flask interior
let flaskInterior = CGMutablePath()
flaskInterior.addLines(between: [
    CGPoint(x: neckLeft, y: neckBottom),
    CGPoint(x: bodyLeft, y: bodyBottom),
    CGPoint(x: bodyRight, y: bodyBottom),
    CGPoint(x: neckRight, y: neckBottom),
])
flaskInterior.closeSubpath()
ctx.addPath(flaskInterior)
ctx.clip()

// Liquid level (about 55% up the flask body)
let liquidY = bodyBottom - (bodyBottom - neckBottom) * 0.42

// Fill liquid
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
let liquidPath = CGMutablePath()
liquidPath.addLines(between: [
    CGPoint(x: bodyLeft - 10, y: bodyBottom + 10),
    CGPoint(x: bodyRight + 10, y: bodyBottom + 10),
    CGPoint(x: bodyRight + 10, y: liquidY),
    CGPoint(x: bodyLeft - 10, y: liquidY),
])
liquidPath.closeSubpath()
ctx.addPath(liquidPath)
ctx.fillPath()

// Liquid surface line (slightly wavy)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
ctx.setLineWidth(S * 0.008)
ctx.move(to: CGPoint(x: bodyLeft - 5, y: liquidY + S * 0.006))
ctx.addQuadCurve(to: CGPoint(x: bodyRight + 5, y: liquidY + S * 0.006),
                 control: CGPoint(x: cx, y: liquidY - S * 0.01))
ctx.strokePath()

ctx.restoreGState()

// MARK: 4. Atom orbits around flask (decorative)

let orbitCx = cx
let orbitCy = S * 0.52
let orbitR = S * 0.28

ctx.setLineWidth(S * 0.012)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))

// 2 orbital ellipses at 60° intervals (reduced from 3 for small-size clarity)
let orbitRx = orbitR
let orbitRy = orbitR * 0.38

for i in 0..<2 {
    let angle = CGFloat(i) * .pi / 3
    ctx.saveGState()
    ctx.translateBy(x: orbitCx, y: orbitCy)
    ctx.rotate(by: angle)
    ctx.addEllipse(in: CGRect(x: -orbitRx, y: -orbitRy, width: orbitRx * 2, height: orbitRy * 2))
    ctx.strokePath()
    ctx.restoreGState()
}

// Nucleus dot at center
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
ctx.addArc(center: CGPoint(x: orbitCx, y: orbitCy), radius: S * 0.022,
           startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.fillPath()

// MARK: Save PNG

guard let cgImage = ctx.makeImage() else {
    fputs("Failed to create image\n", stderr)
    exit(1)
}

let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to create PNG data\n", stderr)
    exit(1)
}

let outPath = "AppIcon_1024.png"
try pngData.write(to: URL(fileURLWithPath: outPath))
print("✅ Generated \(outPath) (\(Int(S))×\(Int(S)))")
