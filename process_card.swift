#!/usr/bin/env swift

import Foundation
import AppKit
import Vision
import CoreImage

// Usage: process_card.swift <input_image> <output_image>
// Outputs OCR text to stdout

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: process_card.swift <input_image> <output_jpg>\n", stderr)
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

// Load image
guard let inputURL = URL(string: "file://" + inputPath),
      let ciImage = CIImage(contentsOf: inputURL) else {
    // Try alternate loading via NSImage
    guard let nsImage = NSImage(contentsOfFile: inputPath),
          let tiffData = nsImage.tiffRepresentation,
          let ciImg = CIImage(data: tiffData) else {
        fputs("Error: Cannot load image at \(inputPath)\n", stderr)
        exit(1)
    }
    processImage(ciImg)
    exit(0) // processImage handles exit
}

processImage(ciImage)

func processImage(_ originalImage: CIImage) {
    let context = CIContext()

    // Step 1: Detect rectangle (business card)
    let rectRequest = VNDetectRectanglesRequest()
    rectRequest.minimumConfidence = 0.5
    rectRequest.minimumAspectRatio = 0.4
    rectRequest.maximumAspectRatio = 1.0
    rectRequest.maximumObservations = 1

    let handler = VNImageRequestHandler(ciImage: originalImage, options: [:])
    try? handler.perform([rectRequest])

    var processedImage: CIImage

    if let rect = rectRequest.results?.first {
        // Get corner points in image coordinates
        let imageWidth = originalImage.extent.width
        let imageHeight = originalImage.extent.height

        let topLeft = CGPoint(
            x: rect.topLeft.x * imageWidth,
            y: rect.topLeft.y * imageHeight
        )
        let topRight = CGPoint(
            x: rect.topRight.x * imageWidth,
            y: rect.topRight.y * imageHeight
        )
        let bottomLeft = CGPoint(
            x: rect.bottomLeft.x * imageWidth,
            y: rect.bottomLeft.y * imageHeight
        )
        let bottomRight = CGPoint(
            x: rect.bottomRight.x * imageWidth,
            y: rect.bottomRight.y * imageHeight
        )

        // Step 2: Perspective correction
        let corrected = originalImage.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: topLeft),
            "inputTopRight": CIVector(cgPoint: topRight),
            "inputBottomLeft": CIVector(cgPoint: bottomLeft),
            "inputBottomRight": CIVector(cgPoint: bottomRight)
        ])

        processedImage = corrected
        fputs("Rectangle detected, perspective corrected.\n", stderr)
    } else {
        // No rectangle found — use original image as-is
        processedImage = originalImage
        fputs("No rectangle detected, using original image.\n", stderr)
    }

    // Step 3: Render to white background JPG
    let extent = processedImage.extent

    // Create white background
    let whiteBG = CIImage(color: CIColor.white).cropped(to: extent)
    let composited = processedImage.composited(over: whiteBG)

    // Export as JPEG
    guard let cgImage = context.createCGImage(composited, from: extent) else {
        fputs("Error: Failed to render image\n", stderr)
        exit(1)
    }

    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
        fputs("Error: Failed to create JPEG\n", stderr)
        exit(1)
    }

    let outputURL = URL(fileURLWithPath: outputPath)
    do {
        try jpegData.write(to: outputURL)
        fputs("Saved processed image to \(outputPath)\n", stderr)
    } catch {
        fputs("Error: Failed to write output: \(error)\n", stderr)
        exit(1)
    }

    // Step 4: OCR on the processed image
    let ocrRequest = VNRecognizeTextRequest()
    ocrRequest.recognitionLevel = .accurate
    ocrRequest.recognitionLanguages = ["zh-Hant", "zh-Hans", "en"]
    ocrRequest.usesLanguageCorrection = true

    let ocrHandler = VNImageRequestHandler(ciImage: processedImage, options: [:])
    do {
        try ocrHandler.perform([ocrRequest])
    } catch {
        fputs("OCR Error: \(error)\n", stderr)
        exit(1)
    }

    guard let observations = ocrRequest.results else {
        fputs("No OCR results\n", stderr)
        exit(0)
    }

    // Output each recognized line to stdout
    for observation in observations {
        if let candidate = observation.topCandidates(1).first {
            print(candidate.string)
        }
    }
}
