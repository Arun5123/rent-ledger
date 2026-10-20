import 'package:flutter_test/flutter_test.dart';
import 'package:rentledger/data/repositories/cloudinary_storage_repository.dart';

void main() {
  group('Cloudinary URL parser', () {
    test('extracts publicId from versioned image URL', () {
      const url =
          'https://res.cloudinary.com/sqfv2g1n/image/upload/v1792477685/users/test/properties/ypnohmuatfbx6ndj3cq7.png';
      expect(
        CloudinaryStorageRepository.extractPublicId(url),
        'users/test/properties/ypnohmuatfbx6ndj3cq7',
      );
      expect(
        CloudinaryStorageRepository.extractResourceType(url),
        'image',
      );
    });

    test('extracts publicId from unversioned image URL', () {
      const url =
          'https://res.cloudinary.com/sqfv2g1n/image/upload/users/p1/photo.jpg';
      expect(
        CloudinaryStorageRepository.extractPublicId(url),
        'users/p1/photo',
      );
      expect(
        CloudinaryStorageRepository.extractResourceType(url),
        'image',
      );
    });

    test('extracts publicId from raw resource URL retaining extension', () {
      const url =
          'https://res.cloudinary.com/sqfv2g1n/raw/upload/v1792477540/document.pdf';
      expect(
        CloudinaryStorageRepository.extractPublicId(url),
        'document.pdf',
      );
      expect(
        CloudinaryStorageRepository.extractResourceType(url),
        'raw',
      );
    });
  });
}

