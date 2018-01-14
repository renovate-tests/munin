//
//  Album.swift
//  g
//
//  Created by Kristoffer Andreas Dalby on 25/12/2017.
//

import Foundation
import Logger

struct Album: Hashable, Comparable {
    static func ==(lhs: Album, rhs: Album) -> Bool {
        return lhs.name == rhs.name
    }
    
    static func <(lhs: Album, rhs: Album) -> Bool {
        return lhs.name < rhs.name
    }
    
    var hashValue: Int {
        return name.lengthOfBytes(using: .utf8) ^ url.lengthOfBytes(using: .utf8) &* 16777619
    }
    
    var name: String
    var url: String
    var path: String
    var photos: Set<Photo>
    var albums: Set<Album>
    var keywords: Set<String>
    var people: Set<String>

    
    init(name: String, path: String) {
        self.name = name
        self.path = path
        self.url = joinPath(paths: path, "index.json")
        self.photos = []
        self.albums = []
        self.keywords = Set()
        self.people = Set()
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case url
        case path
        case photos
        case albums
        case keywords
        case people
    }
    
    func numberOfPhotos(travers: Bool) -> Int {
        if travers {
            return albums.map({$0.numberOfPhotos(travers: travers)}).reduce(0, +) + photos.count
        }
        return photos.count
    }
    
    func numberOfAlbums(travers: Bool) -> Int {
        if travers {
            return albums.map({$0.numberOfAlbums(travers: travers)}).reduce(0, +) + albums.count
        }
        return albums.count
    }
}

extension Album: Encodable {
    func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(path, forKey: .path)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(people, forKey: .people)

        var photosContainer = container.nestedUnkeyedContainer(
            forKey: .photos)
        
        try photos.forEach {
            try photosContainer.encode($0.url)
        }
        
        var albumsContainer = container.nestedUnkeyedContainer(
            forKey: .albums)
        
        try albums.forEach {
            try albumsContainer.encode($0.url)
        }
        
//        var keywordsContainer = container.nestedUnkeyedContainer(
//            forKey: .keywords)
        
//        try keywords.forEach {
//            try keywordsContainer.encode($0.url)
//        }
//
//        var peopleContainer = container.nestedUnkeyedContainer(
//            forKey: .people)
//
//        try people.forEach {
//            try peopleContainer.encode($0.url)
//        }

    }
}


extension Album: Decodable {
    init(from decoder: Decoder) throws
    {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try values.decode(String.self, forKey: .name)
        self.url = try values.decode(String.self, forKey: .url)
        self.path = try values.decode(String.self, forKey: .path)
        self.keywords = try values.decode(Set<String>.self, forKey: .keywords)
        self.people = try values.decode(Set<String>.self, forKey: .people)

        
        //        self.photos = try values.decode([Photo].self, forKey: .photos)
        //        self.albums = try values.decode([Album].self, forKey: .albums)
        
        var photosArray = try values.nestedUnkeyedContainer(forKey: .photos)
        var photos: Set<Photo> = Set<Photo>()
        while (!photosArray.isAtEnd) {
            let url = try photosArray.decode(String.self)
            if let photo = readAndDecodeJsonFile(Photo.self, atPath: url) {
                photos.insert(photo)
            }
        }
        self.photos = photos
        
        var albumsArray = try values.nestedUnkeyedContainer(forKey: .albums)
        var albums: Set<Album> = Set<Album>()
        while (!albumsArray.isAtEnd) {
            let url = try albumsArray.decode(String.self)
            if let album = readAndDecodeJsonFile(Album.self, atPath: url) {
                albums.insert(album)
            }
        }
        self.albums = albums
        
//        var keywordsArray = try values.nestedUnkeyedContainer(forKey: .keywords)
//        var keywords: Set<Keyword> = Set<Keyword>()
//        while (!keywordsArray.isAtEnd) {
//            let url = try keywordsArray.decode(String.self)
//            if let keyword = readAndDecodeJsonFile(Keyword.self, atPath: url) {
//                keywords.insert(keyword)
//            }
//        }
//        self.keywords = keywords
//
//        var peopleArray = try values.nestedUnkeyedContainer(forKey: .people)
//        var people: Set<Keyword> = Set<Keyword>()
//        while (!peopleArray.isAtEnd) {
//            let url = try peopleArray.decode(String.self)
//            if let person = readAndDecodeJsonFile(Keyword.self, atPath: url) {
//                people.insert(person)
//            }
//        }
//        self.people = people
    }
}

extension Album {
    public func writeToOutputDirectory(config: GalleryConfiguration) -> Void {
        let fm = FileManager()
        do {
            try fm.createDirectory(at: URL(fileURLWithPath: self.path), withIntermediateDirectories: true)
            
            log.info("Writing metadata for album \(self.name)")
            let encoder = JSONEncoder()
            if #available(OSX 10.12, *) {
                encoder.dateEncodingStrategy = .iso8601
            }
            
            if let encodedData = try? encoder.encode(self) {
                do {
                    log.trace("Writing album metadata \(self.name) to \(self.url)")
                    try encodedData.write(to: URL(fileURLWithPath: self.url))
                } catch {
                    log.error("Could not write album \(self.name) to \(self.url) with error: \n\(error)")
                }
            }
            
            for album in self.albums {
                album.writeToOutputDirectory(config: config)
            }
            
            for photo in self.photos {
                photo.write(config: config)
            }
        } catch {
            log.error("Failed creating directory \(self.path) with error: \n\(error)")
        }
    }
}


func readStateFromInputDirectory(atPath: String, outPath: String, name: String, config: GalleryConfiguration) -> Album {
    log.info("Creating album from path: \(joinPath(paths: atPath))")
    let fm = FileManager()
    var album = Album(name: name, path: joinPath(paths: outPath, name))
    if let files = try? fm.contentsOfDirectory(atPath: joinPath(paths: atPath)) {
        for element in files {
            var isDirectory: ObjCBool = ObjCBool(false)
            let exists = fm.fileExists(atPath: joinPath(paths: atPath, element), isDirectory: &isDirectory)
            
            if exists && isDirectory.boolValue {
                album.albums.insert(readStateFromInputDirectory(atPath: joinPath(paths: atPath, element), outPath: joinPath(paths: outPath, name), name: element, config: config))
            } else if exists {
                if let fileNameWithoutExtension = fileNameWithoutExtension(atPath: joinPath(paths: atPath, element)),
                    let fileExtension = fileExtension(atPath: joinPath(paths: atPath, element)) {
                    if config.fileExtentions.contains(fileExtension) {
                        if let photo = readPhotoFromPath(atPath: joinPath(paths: atPath, element), outPath: joinPath(paths: outPath, name), name: fileNameWithoutExtension, fileExtension: fileExtension, config: config) {
                            album.photos.insert(photo)
                            album.keywords = album.keywords.union(photo.keywords)
                            album.people = album.people.union(photo.people)
                        }
                    } else {
                        log.warning("File found, but it was not a photo, path: \(joinPath(paths: atPath, element))")
                    }
                }
            }
        }
    }
    return album
}





func readStateFromOutputDirectory(indexFileAtPath: String) -> Album? {
    return readAndDecodeJsonFile(Album.self, atPath: indexFileAtPath)
}
