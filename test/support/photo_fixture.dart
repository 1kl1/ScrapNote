import 'dart:io';

import 'package:image/image.dart' as img;

/// Small, real JPEG with standard DMS GPS tags and a UTC GPS timestamp.
Future<File> writePhoto(
  File file, {
  int latitude = 37,
  int hour = 9,
  bool gps = true,
  bool southWest = false,
}) async {
  final image = img.Image(width: 32, height: 32);
  if (gps) {
    final tags = image.exif.gpsIfd;
    tags.gpsLatitudeRef = southWest ? 'S' : 'N';
    tags.gpsLongitudeRef = southWest ? 'W' : 'E';
    tags[2] = img.IfdValueRational.list([
      img.IfdValueRational(latitude, 1).toRational(),
      img.IfdValueRational(30, 1).toRational(),
      img.IfdValueRational(0, 1).toRational(),
    ]);
    tags[4] = img.IfdValueRational.list([
      img.IfdValueRational(127, 1).toRational(),
      img.IfdValueRational(15, 1).toRational(),
      img.IfdValueRational(0, 1).toRational(),
    ]);
    tags.gpsDate = '2026:09:04';
    tags[7] = img.IfdValueRational.list([
      img.IfdValueRational(hour, 1).toRational(),
      img.IfdValueRational(2, 1).toRational(),
      img.IfdValueRational(3, 1).toRational(),
    ]);
  }
  return file.writeAsBytes(img.encodeJpg(image));
}
