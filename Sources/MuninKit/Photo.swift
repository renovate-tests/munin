//
//  Photo.swift
//  g
//
//  Created by Kristoffer Andreas Dalby on 25/12/2017.
//

import Dispatch
import Foundation
import Logging

#if CORE_GRAPHICS
  import ImageIO
#else
  import SwiftGD
  import SwiftExif
#endif

struct Photo: Codable, Comparable, Hashable {
  var name: String
  var url: String
  var originalImageURL: String
  var originalImagePath: String
  var scaledPhotos: [ScaledPhoto]
  var parents: [Parent]

  // Metadata
  var aperture: Double?
  var apertureFormatted: String?
  var cameraMake: String?
  var cameraModel: String?
  var copyright: String?
  var dateTime: Date?
  var exposureTime: Double?
  var exposureTimeFormatted: String?
  var fNumber: Double?
  var fNumberFormatted: String?
  var focalLength: Double?
  var focalLengthFormatted: String?
  var gps: GPS?
  var height: Int?
  var imageDescription: String?
  var isoSpeed: Set<Int>
  var lensModel: String?
  var location: LocationData?
  var meteringMode: Int?
  var meteringModeFormatted: String?
  var modifiedDate: Date
  var orientation: Orientation?
  var owner: String?
  var shutterSpeed: Double?
  var shutterSpeedFormatted: String?
  var width: Int?

  var keywords: Set<KeywordPointer>
  var people: Set<KeywordPointer>
  var next: String?
  var previous: String?

  init(
    name: String,
    url: String,
    originalImageURL: String,
    originalImagePath: String,
    scaledPhotos: [ScaledPhoto],
    modifiedDate: Date,
    parents: [Parent]
  ) {
    self.name = name
    self.url = url
    self.originalImageURL = originalImageURL
    self.originalImagePath = originalImagePath
    self.scaledPhotos = scaledPhotos
    self.parents = parents
    self.modifiedDate = modifiedDate
    isoSpeed = []
    keywords = []
    people = []
  }
}

struct ScaledPhoto: Codable, AutoEquatable {
  var url: String
  var maxResolution: Int
}

struct GPS: Codable, AutoEquatable {
  var altitude: Double
  var latitude: Double
  var longitude: Double
}

struct LocationData: Codable, AutoEquatable {
  var city: String
  var state: String
  var locationCode: String
  var locationName: String
}

enum Orientation: String, Codable {
  case landscape
  case portrait
}

extension Photo: AutoEquatable {
  static func < (lhs: Photo, rhs: Photo) -> Bool {
    return lhs.name < rhs.name
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(url)
  }
}

extension Photo {
  func write(ctx: Context, writeJson: Bool, writeImage: Bool) {
    log.trace("Photo: \(name) has \(writeImage)")
    // Only write images and symlink if the user wants to
    if writeImage {
      log.trace("Writing image \(name)")
      let fileURL = URL(fileURLWithPath: originalImagePath)
      #if CORE_GRAPHICS
        if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
          for scaledPhoto in scaledPhotos {
            if let resizedImageData = resizeImageCoreGraphics(
              imageSource: imageSource,
              maxResolution: scaledPhoto.maxResolution,
              compression: CGFloat(ctx.config.jpegCompression)
            ) {
              log.trace(
                "Writing image \(name) at \(scaledPhoto.maxResolution)px to \(scaledPhoto.url)")
              do {
                try resizedImageData.write(to: URL(fileURLWithPath: scaledPhoto.url))
              } catch {
                log.error(
                  "Could not write image \(name) to \(scaledPhoto.url) with error: \n\(error)")
              }
            }
          }
        }
      #else
        if let image = Image(url: fileURL) {
          for scaledPhoto in scaledPhotos {
            if let resizedImage = image.resizedTo(width: scaledPhoto.maxResolution) {
              log.trace(
                "Writing image \(name) at \(scaledPhoto.maxResolution)px to \(scaledPhoto.url)")
              if !resizedImage.write(
                to: URL(fileURLWithPath: scaledPhoto.url),
                quality: Int(100 * ctx.config.jpegCompression))
              {
                log.error("Could not write image \(name) to \(scaledPhoto.url)")
              }
            }
          }
        }
      #endif

      let relativeOriginialPath = Array(repeating: "..", count: depth()) + [originalImagePath]
      log.trace("Symlinking original image \(name) to \(originalImageURL)")
      do {
        try createOrReplaceSymlink(
          source: joinPath(paths: relativeOriginialPath),
          destination: originalImageURL
        )
      } catch {
        log.error("Could not symlink image \(name) to \(originalImageURL) with error: \n\(error)")
      }
    }

    if writeJson {
      log.trace("Writing metadata for image \(name)")
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601

      if let encodedData = try? encoder.encode(self) {
        do {
          log.trace("Writing image metadata \(name) to \(url)")
          try encodedData.write(to: URL(fileURLWithPath: url))
        } catch {
          log.error("Could not write image \(name) to \(url) with error: \n\(error)")
        }
      }
    }
  }

  func destroy(ctx: Context) {
    let fileManager = FileManager()
    log.trace("Removing image \(name)")
    let jsonURL = URL(fileURLWithPath: url)
    let symlinkedImageURL = URL(fileURLWithPath: originalImageURL)
    do {
      try fileManager.removeItem(at: jsonURL)
    } catch {
      log.error("Could not remove image json \(name) at path \(url)")
    }

    do {
      try fileManager.removeItem(at: symlinkedImageURL)
    } catch {
      log.error("Could not remove image json \(name) at path \(originalImageURL)")
    }

    for scaledPhoto in scaledPhotos {
      let fileURL = URL(fileURLWithPath: scaledPhoto.url)
      do {
        try fileManager.removeItem(at: fileURL)
      } catch {
        log.error("Could not remove image \(name) at path \(scaledPhoto.url)")
      }
    }
  }

  func depth() -> Int {
    let urlSeparator: Character = "/"
    var counter = 0
    for char in url where char == urlSeparator {
      counter += 1
    }
    return counter
  }

  func include() -> Bool {
    for keyword in keywords where keyword.name == "NO_HUGIN" {
      return false
    }
    return true
  }
}

#if CORE_GRAPHICS

  // swiftlint:disable cyclomatic_complexity
  // swiftlint:disable function_body_length
  // swiftlint:disable function_parameter_count
  func readPhotoFromPath(
    atPath: String,
    outPath: String,
    name: String,
    fileExtension: String,
    parents: [Parent],
    ctx: Context
  ) -> Photo? {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

    let fileURL = URL(fileURLWithPath: atPath)
    if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
      // Get md5 of original
      //        log.trace("Calculating md5 hash for original image \(name)")
      //        if let imageFile = try? Data(contentsOf: URL(fileURLWithPath: atPath)) {
      //            let md5 = MD5()
      //            let hash = md5.calculate(for: imageFile.bytes)
      //            print(hash.toHexString())
      //        }

      let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
      if let dict = imageProperties as? [String: Any] {
        var photo = Photo(
          name: name,
          url: "\(joinPath(paths: outPath, name)).json",
          originalImageURL: "\(joinPath(paths: outPath, name))_original.\(fileExtension)",
          originalImagePath: atPath,
          scaledPhotos: [],
          // If no modifiation date is available, use now.
          modifiedDate: fileModificationDate(url: fileURL) ?? Date(),
          parents: parents
        )

        photo.width = dict["PixelWidth"] as? Int
        photo.height = dict["PixelHeight"] as? Int

        if let width = photo.width, let height = photo.height {
          if width > height {
            photo.orientation = Orientation.landscape
          } else {
            photo.orientation = Orientation.portrait
          }
        }

        let maxResolution = max(photo.width ?? 0, photo.height ?? 0)

        photo.scaledPhotos = ctx.config.resolutions.filter { $0 < maxResolution }.map({
          ScaledPhoto(
            url: "\(joinPath(paths: outPath, name))_\($0).\(fileExtension)",
            maxResolution: $0
          )
        }
        )

        if let exif = dict["{Exif}"] as? [String: Any] {
          photo.aperture = exif["ApertureValue"] as? Double
          photo.fNumber = exif["FNumber"] as? Double
          photo.meteringMode = exif["MeteringMode"] as? Int
          photo.shutterSpeed = exif["ShutterSpeedValue"] as? Double
          photo.focalLength = exif["FocalLength"] as? Double
          photo.exposureTime = exif["ExposureTime"] as? Double
          if let dateTime = exif["DateTimeOriginal"] as? String {
            photo.dateTime = dateFormatter.date(from: dateTime)
          }

          if let isoSpeed = exif["ISOSpeedRatings"] as? [Int] {
            photo.isoSpeed = Set(isoSpeed)
          }
        } else {
          log.warning("Exif tag not found for photo, some metatags will be unavailable")
        }

        if let tiff = dict["{TIFF}"] as? [String: Any] {
          photo.imageDescription = tiff["ImageDescription"] as? String
          photo.cameraMake = tiff["Make"] as? String
          photo.cameraModel = tiff["Model"] as? String

        } else {
          log.warning("TIFF tag not found for photo, some metatags will be unavailable")
        }

        if let iptc = dict["{IPTC}"] as? [String: Any] {
          // Add location data if available
          if let city = iptc["City"] as? String,
            let state = iptc["Province/State"] as? String,
            let locationCode = iptc["Country/PrimaryLocationCode"] as? String,
            let locationName = iptc["Country/PrimaryLocationName"] as? String
          {
            photo.location = LocationData(
              city: city,
              state: state,
              locationCode: locationCode,
              locationName: locationName)

            // Add location names as keywords
            let stateKeyword = KeywordPointer(
              name: state,
              url: "\(ctx.config.outputPath)/keywords/\(urlifyName(state)).json"
            )
            let locationCodeKeyword = KeywordPointer(
              name: locationCode,
              url: "\(ctx.config.outputPath)/keywords/\(urlifyName(locationCode)).json"
            )
            let locationNameKeyword = KeywordPointer(
              name: locationName,
              url: "\(ctx.config.outputPath)/keywords/\(urlifyName(locationName)).json"
            )

            photo.keywords.insert(stateKeyword)
            photo.keywords.insert(locationCodeKeyword)
            photo.keywords.insert(locationNameKeyword)
          }

          photo.copyright = iptc["CopyrightNotice"] as? String

          if let keywords = iptc["Keywords"] as? [String] {
            for keyword in keywords {
              let keywordPointer = KeywordPointer(
                name: keyword,
                url: "\(ctx.config.outputPath)/keywords/\(urlifyName(keyword)).json"
              )
              if ctx.config.people.contains(keyword) {
                photo.people.insert(keywordPointer)
              } else {
                photo.keywords.insert(keywordPointer)
              }
            }
          }
        } else {
          log.warning("IPTC tag not found for photo, some metatags will be unavailable")
        }

        if let exifAux = dict["{ExifAux}"] as? [String: Any] {
          photo.lensModel = exifAux["LensModel"] as? String
          photo.owner = exifAux["OwnerName"] as? String

        } else {
          log.warning("ExifAux tag not found for photo, some metatags will be unavailable")
        }

        if let gpsDict = dict["{GPS}"] as? [String: Any] {
          if let altitude = gpsDict["Altitude"] as? Double,
            let latitude = gpsDict["Latitude"] as? Double,
            let longitude = gpsDict["Longitude"] as? Double,
            let longitudeRef = gpsDict["LongitudeRef"] as? String,
            let latitudeRef = gpsDict["LatitudeRef"] as? String
          {
            photo.gps = GPS(
              altitude: altitude,
              latitude: latitudeRef == "N" ? latitude : latitude * -1,
              longitude: longitudeRef == "E" ? longitude : longitude * -1
            )
          }
        } else {
          log.warning("GPS tag not found for photo, some metatags will be unavailable")
        }

        return photo
      }
    }
    return nil
  }

#else

  func readPhotoFromPath(
    atPath: String,
    outPath: String,
    name: String,
    fileExtension: String,
    parents: [Parent],
    ctx: Context
  ) -> Photo? {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

    let fileURL = URL(fileURLWithPath: atPath)

    let exifImage = SwiftExif.Image(imagePath: fileURL)
    let exifDict = exifImage.Exif()
    let exifRawDict = exifImage.ExifRaw()
    let iptcDict = exifImage.Iptc()

    var photo = Photo(
      name: name,
      url: "\(joinPath(paths: outPath, name)).json",
      originalImageURL: "\(joinPath(paths: outPath, name))_original.\(fileExtension)",
      originalImagePath: atPath,
      scaledPhotos: [],
      // If no modifiation date is available, use now.
      modifiedDate: fileModificationDate(url: fileURL) ?? Date(),
      parents: parents
    )

    // Use GD to check for the width/height
    if let image = Image(url: fileURL) {
      photo.width = image.size.width
      photo.height = image.size.height
    }

    if let exif = exifRawDict["EXIF"] {
      if let aperture = exif["Aperture"] {
        photo.aperture = Double(aperture)
      }

      if let fNumber = exif["F-Number"] {
        photo.fNumber = Double(fNumber)
      }
      if let meteringMode = exif["Metering Mode"] {
        photo.meteringMode = Int(meteringMode)
      }
      if let shutterSpeed = exif["Shutter Speed"] {
        photo.shutterSpeed = Double(shutterSpeed)
      }
      if let focalLength = exif["Focal Length"] {
        photo.focalLength = Double(focalLength)
      }
      if let exposureTime = exif["Exposure Time"] {
        photo.exposureTime = Double(exposureTime)
      }
    }

    if let exif = exifDict["EXIF"] {
      if let width = exif["Pixel X Dimension"] {
        if let _ = photo.width {
          log.trace("Width already set, ignoring EXIF width")
        } else {
          photo.width = Int(width)
        }
      }

      if let height = exif["Pixel Y Dimension"] {
        if let _ = photo.height {
          log.trace("Height already set, ignoring EXIF height")
        } else {
          photo.height = Int(height)
        }
      }

      if let aperture = exif["Aperture"] {
        photo.apertureFormatted = aperture
      }

      if let fNumber = exif["F-Number"] {
        photo.fNumberFormatted = fNumber
      }
      if let meteringMode = exif["Metering Mode"] {
        photo.meteringModeFormatted = meteringMode
      }
      if let shutterSpeed = exif["Shutter Speed"] {
        photo.shutterSpeedFormatted = shutterSpeed
      }
      if let focalLength = exif["Focal Length"] {
        photo.focalLengthFormatted = focalLength
      }
      if let exposureTime = exif["Exposure Time"] {
        photo.exposureTimeFormatted = exposureTime
      }

      if let isoSpeedStr = exif["ISO Speed Ratings"] {
        if let isoSpeed = Int(isoSpeedStr) {
          photo.isoSpeed = Set([isoSpeed])
        }
      }
      if let dateTime = exif["Date and Time (Original)"] {
        photo.dateTime = dateFormatter.date(from: dateTime)
      }

      photo.lensModel = exif["Lens Model"]
      photo.owner = exif["Camera Owner Name"]

    } else {
      log.warning("Exif tag not found for photo, some metatags will be unavailable")
    }

    if let width = photo.width, let height = photo.height {
      if width > height {
        photo.orientation = Orientation.landscape
      } else {
        photo.orientation = Orientation.portrait
      }
    }

    let maxResolution = max(photo.width ?? 0, photo.height ?? 0)

    photo.scaledPhotos = ctx.config.resolutions.filter { $0 < maxResolution }.map({
      ScaledPhoto(
        url: "\(joinPath(paths: outPath, name))_\($0).\(fileExtension)",
        maxResolution: $0
      )
    }
    )

    if let zero = exifDict["0"] {
      photo.cameraMake = zero["Manufacturer"]
      photo.cameraModel = zero["Model"]
      photo.copyright = zero["Artist"] ?? zero["Copyright"]

    } else {
      log.warning("'0' (zero) tag not found for photo, some metatags will be unavailable")
    }

    // Add location data if available
    if let city = iptcDict["City"] as? String,
      let state = iptcDict["Province/State"] as? String,
      let locationCode = iptcDict["Country Code"] as? String,
      let locationName = iptcDict["Country Name"] as? String
    {
      photo.location = LocationData(
        city: city,
        state: state,
        locationCode: locationCode,
        locationName: locationName)

      // Add location names as keywords
      let stateKeyword = KeywordPointer(
        name: state,
        url: "\(ctx.config.outputPath)/keywords/\(urlifyName(state)).json"
      )
      let locationCodeKeyword = KeywordPointer(
        name: locationCode,
        url: "\(ctx.config.outputPath)/keywords/\(urlifyName(locationCode)).json"
      )
      let locationNameKeyword = KeywordPointer(
        name: locationName,
        url: "\(ctx.config.outputPath)/keywords/\(urlifyName(locationName)).json"
      )

      photo.keywords.insert(stateKeyword)
      photo.keywords.insert(locationCodeKeyword)
      photo.keywords.insert(locationNameKeyword)
    }

    if let keywords = iptcDict["Keywords"] as? [String] {
      for keyword in keywords {
        let keywordPointer = KeywordPointer(
          name: keyword,
          url: "\(ctx.config.outputPath)/keywords/\(urlifyName(keyword)).json"
        )
        if ctx.config.people.contains(keyword) {
          photo.people.insert(keywordPointer)
        } else {
          photo.keywords.insert(keywordPointer)
        }
      }
    }

    if let gpsDict = exifDict["GPS"] {
      if let altitudeStr = gpsDict["Altitude"],
        let latitudeStr = gpsDict["Latitude"],
        let longitudeStr = gpsDict["Longitude"]
      {
        if let altitude = Double(altitudeStr),
          let latitude = LocationDegree.fromString(latitudeStr),
          let longitude = LocationDegree.fromString(longitudeStr),
          let longitudeRef = gpsDict["East or West Longitude"],
          let latitudeRef = gpsDict["North or South Latitude"]
        {
          photo.gps = GPS(
            altitude: altitude,
            latitude: latitudeRef == "N"
              ? latitude.toDecimal()
              : latitude.toDecimal() * -1,
            longitude: longitudeRef == "E" ? longitude.toDecimal() : longitude.toDecimal() * -1
          )
        }

      }

    } else {
      log.warning("GPS tag not found for photo, some metatags will be unavailable")
    }

    return photo
  }

#endif
