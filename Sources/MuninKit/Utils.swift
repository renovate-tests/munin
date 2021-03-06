//
//  Utils.swift
//  galPackageDescription
//
//  Created by Kristoffer Andreas Dalby on 25/12/2017.
//

import Foundation
import Logging

func readAndDecodeJsonFile<T>(_ type: T.Type, atPath: String) -> T? where T: Decodable {
  let fileManager = FileManager()
  var isDirectory: ObjCBool = ObjCBool(false)
  let exists = fileManager.fileExists(atPath: atPath, isDirectory: &isDirectory)

  if exists, !isDirectory.boolValue {
    if let indexFile = try? Data(contentsOf: URL(fileURLWithPath: atPath)) {
      log.info("Decoding \(atPath)")
      let decoder = JSONDecoder()
      if #available(OSX 10.12, *) {
        decoder.dateDecodingStrategy = .iso8601
      }

      if let decodedData = try? decoder.decode(type, from: indexFile) {
        return decodedData
      } else {
        log.error("Could not decode \(atPath)")
      }
    } else {
      log.error("Could not read \(atPath)")
    }
  } else {
    log.error("File \(atPath) does not exist")
  }
  return nil
}

func createOrReplaceSymlink(source: String, destination: String) throws {
  let fileManager = FileManager()

  var isDirectory: ObjCBool = ObjCBool(false)
  let exists = fileManager.fileExists(atPath: destination, isDirectory: &isDirectory)
  if exists || isDirectory.boolValue {
    log.trace("Symlink exists, removing \(destination)")
    try fileManager.removeItem(atPath: destination)
  }

  try fileManager.createSymbolicLink(atPath: destination, withDestinationPath: source)
}

func joinPath(paths: String...) -> String {
  return paths.filter { $0 != "" }.joined(separator: "/")
}

func joinPath(paths: [String]) -> String {
  return paths.filter { $0 != "" }.joined(separator: "/")
}

func fileExtension(atPath: String) -> String? {
  let url = URL(fileURLWithPath: atPath)
  return url.pathExtension
}

func fileNameWithoutExtension(atPath: String) -> String {
  let url = URL(fileURLWithPath: atPath)
  let fileName = url.lastPathComponent
  let fileExtension = url.pathExtension
  return fileName.replacingOccurrences(of: ".\(fileExtension)", with: "")
}

func pathWithoutFileName(atPath: String) -> String {
  let url = URL(fileURLWithPath: atPath)
  return url.deletingLastPathComponent().relativeString
}

#if CORE_GRAPHICS
  func resizeImageCoreGraphics(imageSource: CGImageSource, maxResolution: Int, compression: CGFloat)
    -> Data?
  {
    // get source properties so we retain metadata (EXIF) for the downsized image
    if var metaData = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
      let width = metaData[kCGImagePropertyPixelWidth as String] as? Int,
      let height = metaData[kCGImagePropertyPixelHeight as String] as? Int
    {
      let srcMaxResolution = max(width, height)

      // if source resolution is larger than the scaled resolution, scale down image
      if srcMaxResolution >= maxResolution {
        let scaleOptions =
          [
            kCGImageSourceThumbnailMaxPixelSize as String: maxResolution,
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
          ] as [String: Any]

        if let scaledImage = CGImageSourceCreateThumbnailAtIndex(
          imageSource, 0, scaleOptions as CFDictionary)
        {
          // add compression ratio to desitnation options
          metaData[kCGImageDestinationLossyCompressionQuality as String] = compression

          // create new jpeg
          let newImageData = NSMutableData()
          if let cgImageDestination = CGImageDestinationCreateWithData(
            newImageData, kUTTypeJPEG, 1, nil)
          {
            CGImageDestinationAddImage(cgImageDestination, scaledImage, metaData as CFDictionary)
            CGImageDestinationFinalize(cgImageDestination)

            return newImageData as Data
          }
        }
      }
    }
    return nil
  }
#endif

extension Date {
  var millisecondsSince1970: Int64 {
    return Int64((timeIntervalSince1970 * 1000.0).rounded())
  }

  init(milliseconds: Int64) {
    self = Date(timeIntervalSince1970: TimeInterval(milliseconds / 1000))
  }
}

// When the modified date is encoded to json, the millisecond accuracy is lost.
// Therefore we remove it before so we can do a proper equal of the picture to
// seconds accuracy.
func fileModificationDate(url: URL) -> Date? {
  do {
    let attr = try FileManager.default.attributesOfItem(atPath: url.path)
    if let date = attr[FileAttributeKey.modificationDate] as? Date {
      let rounded = date.millisecondsSince1970 - (date.millisecondsSince1970 % 1000)
      let roundedDate = Date(milliseconds: rounded)
      return roundedDate
    }
    return nil
  } catch {
    return nil
  }
}

func prettyPrintAlbum(_ album: Album) {
  let indentCharacter = "  "
  func prettyPrintAlbumRecursive(_ album: Album, indent: Int) {
    let indentString = String(repeating: indentCharacter, count: indent)
    let indentChildString = String(repeating: indentCharacter, count: indent + 1)

    // TODO: Determine of this should be log or print
    print("\(indentString)Album: \(album.name): \(album.path)")
    for photo in album.photos {
      // TODO: Determine of this should be log or print
      print("\(indentChildString)Photo: \(photo.name): \(photo.url)")
    }
    for childAlbum in album.albums {
      prettyPrintAlbumRecursive(childAlbum, indent: indent + 1)
    }
  }
  prettyPrintAlbumRecursive(album, indent: 0)
}

func prettyPrintAdded(_ album: Album) {
  prettyPrintAlbumCompact(album, marker: "[+]".green)
}

func prettyPrintRemoved(_ album: Album) {
  prettyPrintAlbumCompact(album, marker: "[-]".red)
}

func prettyPrintAlbumCompact(_ album: Album, marker: String) {
  if !album.photos.isEmpty {
    print("Album: \(album.url)")
  }
  for photo in album.photos {
    print("\(marker): \(photo.url)")
  }

  for childAlbum in album.albums {
    prettyPrintAlbumCompact(childAlbum, marker: marker)
  }
}

func urlifyName(_ name: String) -> String {
  return name.replacingOccurrences(of: " ", with: "_")
}

extension Collection {
  /// Returns the element at the specified index iff it is within bounds, otherwise nil.
  subscript(safe index: Index) -> Element? {
    return indices.contains(index) ? self[index] : nil
  }
}

func prettyPrintDiff(added: Album?, removed: Album?) -> String {
  var str = ""
  if let a = added {
    let astr = """

      Added:
      \(prettyPrintAdded(a))

      """

    str = str + astr
  }
  if let r = removed {
    let rstr = """

      Removed:
      \(prettyPrintRemoved(r))

      """

    str = str + rstr
  }
  return str
}

func diff(new: Album, old: Album) -> (Album?, Album?) {
  if new == old {
    return (nil, nil)
  }

  var removed = new.copyWithoutChildren()
  var added = new.copyWithoutChildren()

  removed.photos = old.photos.subtracting(new.photos)
  added.photos = new.photos.subtracting(old.photos)

  // Not changed
  _ = new.albums.intersection(old.albums)
  let onlyNewAlbums = new.albums.subtracting(old.albums)
  let onlyOldAlbums = old.albums.subtracting(new.albums)

  let changedAlbums = pairChangedAlbums(
    newAlbums: Array(onlyNewAlbums), oldAlbums: Array(onlyOldAlbums))

  for changed in changedAlbums {
    if let newChangedAlbum = changed.0,
      let oldChangedAlbum = changed.1
    {
      let (addedChild, removedChild) = diff(new: newChangedAlbum, old: oldChangedAlbum)

      if let child = addedChild {
        added.albums.insert(child)
      }

      if let child = removedChild {
        removed.albums.insert(child)
      }
    } else if let newChangedAlbum = changed.0 {
      added.albums.insert(newChangedAlbum)
    } else if let oldChangedAlbum = changed.1 {
      removed.albums.insert(oldChangedAlbum)
    }
  }

  return (added, removed)
}

func pairChangedAlbums(newAlbums: [Album], oldAlbums: [Album]) -> ([(Album?, Album?)]) {
  var pairs: [(Album?, Album?)] = []

  for new in newAlbums {
    if isAlbumInListByName(album: new, albums: oldAlbums) {
      for old in oldAlbums where new.name == old.name {
        pairs.append((new, old))
      }
    } else {
      pairs.append((new, nil))
    }
  }
  for old in oldAlbums {
    if !isAlbumInListByName(album: old, albums: newAlbums) {
      pairs.append((nil, old))
    }
  }

  return pairs
}

func isAlbumInListByName(album: Album, albums: [Album]) -> Bool {
  for item in albums where album.name == item.name {
    return true
  }
  return false
}
