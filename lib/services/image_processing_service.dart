import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

class ImageProcessingService {
  /// Applies auto-enhance (contrast and brightness adjustment).
  Future<File> autoEnhance(File imageFile) async {
    return compute(_processAutoEnhance, imageFile);
  }

  /// Converts image to grayscale.
  Future<File> toGrayscale(File imageFile) async {
    return compute(_processGrayscale, imageFile);
  }

  static Future<File> _processAutoEnhance(File file) async {
    final bytes = await file.readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return file;

    // 1. Extreme contrast and brightness boost
    // Push the gray "paper" closer to the white threshold
    image = img.adjustColor(image, contrast: 2.5, brightness: 0.1, gamma: 1.6);

    // 2. Definitive background whitening
    // Any pixel that is 70% bright or more gets pushed to pure white
    for (final pixel in image) {
      final double luminance =
          (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114);
      if (luminance > 180) {
        // Aggressive threshold for gray paper
        pixel.r = 255;
        pixel.g = 255;
        pixel.b = 255;
      }
    }

    final encoded = img.encodeJpg(image, quality: 95);
    await file.writeAsBytes(encoded);
    return file;
  }

  static Future<File> _processGrayscale(File file) async {
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return file;

    final grayscale = img.grayscale(image);

    final encoded = img.encodeJpg(grayscale, quality: 90);
    await file.writeAsBytes(encoded);
    return file;
  }
}
