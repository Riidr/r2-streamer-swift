//
//  OPFMeta.swift
//  r2-streamer-swift
//
//  Created by Mickaël Menu on 04.06.19.
//
//  Copyright 2019 Readium Foundation. All rights reserved.
//  Use of this source code is governed by a BSD-style license which is detailed
//  in the LICENSE file present in the project repository where this source code is maintained.
//

import Foundation
import Fuzi
import R2Shared


/// Package vocabularies used for `property`, `properties`, `scheme` and `rel`.
/// http://www.idpf.org/epub/301/spec/epub-publications.html#sec-metadata-assoc
enum OPFVocabulary: String {
    // Fallback prefixes for metadata's properties and links' rels.
    case defaultMetadata, defaultLinkRel
    // Reserved prefixes (https://idpf.github.io/epub-prefixes/packages/).
    case a11y, dcterms, epubsc, marc, media, onix, rendition, schema, xsd
    // Additional prefixes used in the streamer.
    case dc, calibre

    var uri: String {
        switch self {
        case .defaultMetadata:
            return "http://idpf.org/epub/vocab/package/#"
        case .defaultLinkRel:
            return "http://idpf.org/epub/vocab/package/link/#"
        case .a11y:
            return "http://www.idpf.org/epub/vocab/package/a11y/#"
        case .dcterms:
            return "http://purl.org/dc/terms/"
        case .epubsc:
            return "http://idpf.org/epub/vocab/sc/#"
        case .marc:
            return "http://id.loc.gov/vocabulary/"
        case .media:
            return "http://www.idpf.org/epub/vocab/overlays/#"
        case .onix:
            return "http://www.editeur.org/ONIX/book/codelists/current.html#"
        case .rendition:
            return "http://www.idpf.org/vocab/rendition/#"
        case .schema:
            return "http://schema.org/"
        case .xsd:
            return "http://www.w3.org/2001/XMLSchema#"
        case .dc:
            return "http://purl.org/dc/elements/1.1/"
        case .calibre:
            // https://github.com/kovidgoyal/calibre/blob/3f903cbdd165e0d1c5c25eecb6eef2a998342230/src/calibre/ebooks/metadata/opf3.py#L170
            return "https://calibre-ebook.com"
        }
    }
    
    /// Returns the property stripped of its prefix, and the associated vocabulary URI for the given metadata property.
    ///
    /// - Parameter prefixes: Custom prefixes declared in the package.
    static func parse(property: String, prefixes: [String: String] = [:]) -> (property: String, vocabularyURI: String) {
        let property = property.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let regex = try! NSRegularExpression(pattern: "^\\s*(\\S+?):\\s*(.+?)\\s*$")
        guard let match = regex.firstMatch(in: property, range: NSRange(property.startIndex..., in: property)),
            let prefixRange = Range(match.range(at: 1), in: property),
            let propertyRange = Range(match.range(at: 2), in: property) else
        {
            return (property, OPFVocabulary.defaultMetadata.uri)
        }
        
        let prefix = String(property[prefixRange])
        return (
            property: String(property[propertyRange]),
            vocabularyURI: prefixes[prefix] ?? (OPFVocabulary(rawValue: prefix) ?? .defaultMetadata).uri
        )
    }
    
    
    /// Parses the custom vocabulary prefixes declared in the given package document.
    /// "Reserved prefixes should not be overridden in the prefix attribute, but Reading Systems must use such local overrides when encountered." (http://www.idpf.org/epub/301/spec/epub-publications.html#sec-metadata-reserved-vocabs)
    static func prefixes(in document: XMLDocument) -> [String: String] {
        document.definePrefix("opf", forNamespace: "http://www.idpf.org/2007/opf")
        guard let prefixAttribute = document.firstChild(xpath: "/opf:package")?.attr("prefix") else {
            return [:]
        }
        return try! NSRegularExpression(pattern: "(\\S+?):\\s*(\\S+)")
            .matches(in: prefixAttribute, range: NSRange(prefixAttribute.startIndex..., in: prefixAttribute))
            .reduce([:]) { prefixes, match in
                guard match.numberOfRanges == 3,
                    let prefixRange = Range(match.range(at: 1), in: prefixAttribute),
                    let uriRange = Range(match.range(at: 2), in: prefixAttribute) else
                {
                    return prefixes
                }
                let prefix = String(prefixAttribute[prefixRange])
                let uri = String(prefixAttribute[uriRange])
                var prefixes = prefixes
                prefixes[prefix] = uri
                return prefixes
        }
    }

}


/// Represents a `meta` tag in an OPF document.
struct OPFMeta {
    let property: String
    /// URI of the property's vocabulary.
    let vocabularyURI: String
    let content: String
    let id: String?
    /// ID of the metadata that is refined by this one, if any.
    let refines: String?
    let element: XMLElement
}


struct OPFMetaList {
    
    private let document: XMLDocument
    private let metas: [OPFMeta]
    
    init(document: XMLDocument) {
        self.document = document
        let prefixes = OPFVocabulary.prefixes(in: document)
        document.definePrefix("opf", forNamespace: "http://www.idpf.org/2007/opf")
        self.metas = document.xpath("/opf:package/opf:metadata/opf:meta")
            .compactMap { meta in
                // EPUB 3
                if let property = meta.attr("property") {
                    let (property, vocabularyURI) = OPFVocabulary.parse(property: property, prefixes: prefixes)
                    var refinedID = meta.attr("refines")
                    refinedID?.removeFirst()  // Get rid of the # before the ID.
                    return OPFMeta(property: property, vocabularyURI: vocabularyURI, content: meta.stringValue, id: meta.attr("id"), refines: refinedID, element: meta)
                // EPUB 2
                } else if let property = meta.attr("name") {
                    let (property, vocabularyURI) = OPFVocabulary.parse(property: property, prefixes: prefixes)
                    return OPFMeta(property: property, vocabularyURI: vocabularyURI, content: meta.attr("content") ?? "", id: nil, refines: nil, element: meta)
                } else {
                    return nil
                }
            }
    }
    
    subscript(_ property: String) -> [OPFMeta] {
        return self[property, in: .defaultMetadata]
    }
    
    subscript(_ property: String, refining id: String) -> [OPFMeta] {
        return self[property, in: .defaultMetadata, refining: id]
    }
    
    subscript(_ property: String, in vocabulary: OPFVocabulary) -> [OPFMeta] {
        return metas.filter { $0.property == property && $0.vocabularyURI == vocabulary.uri }
    }
    
    subscript(_ property: String, in vocabulary: OPFVocabulary, refining id: String) -> [OPFMeta] {
        return metas.filter { $0.property == property && $0.vocabularyURI == vocabulary.uri && $0.refines == id }
    }
    
    /// Returns the JSON representation of the unknown metadata (for RWPM's `Metadata.otherMetadata`)
    var otherMetadata: [String: Any] {
        var metadata: [String: NSMutableOrderedSet] = [:]
        
        // FIXME: is there a better way to handle <dc:*> tags?
        if let metadataElement = document.firstChild(xpath: "/opf:package/opf:metadata") {
            document.definePrefix("dc", forNamespace: "http://purl.org/dc/elements/1.1/")
            metadata[OPFVocabulary.dc.uri + "source"] = NSMutableOrderedSet(array: metadataElement.xpath("dc:source").map { $0.stringValue })
            metadata[OPFVocabulary.dc.uri + "rights"] = NSMutableOrderedSet(array: metadataElement.xpath("dc:rights").map { $0.stringValue })
        }
        
        for meta in metas {
            let isRWPMProperty = (rwpmProperties.first(where: { $0.key.uri == meta.vocabularyURI })?.value.contains(meta.property) ?? false)
            // FIXME: what to do with refines?
            guard meta.refines == nil, !isRWPMProperty else {
                continue
            }
            let key = meta.vocabularyURI + meta.property
            let values = metadata[key] ?? NSMutableOrderedSet()
            values.add(meta.content)
            metadata[key] = values
        }
        
        return metadata.compactMapValues { values in
            switch values.count {
            case 0:
                return nil
            case 1:
                return values[0]
            default:
                return values.array
            }
        }
    }
    
    // List of properties that should not be added to `otherMetadata` because they are already consumed by the RWPM model.
    private let rwpmProperties: [OPFVocabulary: [String]] = [
        .defaultMetadata: ["cover"],
        .dc: ["contributor", "creator", "publisher"],
        .dcterms: ["contributor", "creator", "modified", "publisher"],
        .media: ["duration"],
        .rendition: ["flow", "layout", "orientation", "spread"]
    ]

}
