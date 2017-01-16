//
//  UITestMocking.swift
//  UITestMocking
//
//  Created by Karl von Randow on 15/01/17.
//  Copyright © 2017 XK72. All rights reserved.
//

import Foundation

public class Matching {

    private var matchers = [Matcher]()

    public init() {

    }
    
    public func add(_ path: String) -> Matcher {
        let matcher = Matcher(path)
        matchers.append(matcher)
        return matcher
    }

    public func handle(request: Request) -> Response {
        var bestScore = -1
        var bestMatcher: Matcher?

        for matcher in matchers {
            if let score = matcher.match(request: request) {
                if score >= bestScore {
                    bestScore = score
                    bestMatcher = matcher
                }
            }
        }

        if let matcher = bestMatcher {
            return matcher.handle(request: request)
        } else {
            return Response(status: .notFound)
        }
    }

}

public enum ResponseStatus: Equatable, CustomStringConvertible {
    
    public static func ==(lhs: ResponseStatus, rhs: ResponseStatus) -> Bool {
        return lhs.code == rhs.code && lhs.message == rhs.message
    }

    case notFound
    case ok
    case notModified
    case internalServerError
    case other(code: Int, message: String)
    
    public var code: Int {
        switch self {
        case .notFound: return 404
        case .ok: return 200
        case .notModified: return 304
        case .internalServerError: return 500
        case .other(let code, let message): return code
        }
    }
    
    public var message: String {
        switch self {
        case .notFound: return "Not Found"
        case .ok: return "OK"
        case .notModified: return "Not Modified"
        case .internalServerError: return "Internal Server Error"
        case .other(let code, let message): return message
        }
    }
    
    public var description: String {
        return "\(self.code) \(self.message)"
    }
    
}

public enum ContentType {
    case TextJSON
    case TextPlain
    case TextHTML
    case Other(type: String)

    func type() -> String {
        switch self {
        case .TextJSON:
            return "text/json"
        case .TextPlain:
            return "text/plain"
        case .TextHTML:
            return "text/html"
        case .Other(let aType):
            return aType
        }
    }

    static func forExtension(ext: String) -> ContentType? {
        switch ext.lowercased() {
        case "json":
            return .TextJSON
        case "txt":
            return .TextPlain
        case "html", "htm":
            return .TextHTML
        default:
            return nil
        }
    }
}

public class Matcher {

    private let path: String
    private var params = [String: String]()
    private var allowOtherParams = false
    private var headers = [String: String]()
    private var responder: Responder?

    public init(_ path: String) {
        self.path = path
    }

    @discardableResult public func param(_ name: String, _ value: String) -> Matcher {
        params[name] = value
        return self
    }

    @discardableResult public func anyParams() -> Matcher {
        allowOtherParams = true
        return self
    }

    @discardableResult public func header(_ name: String, _ value: String) -> Matcher {
        headers[name] = value
        return self
    }

    @discardableResult public func respond(_ responder: Responder) -> Matcher {
        return self
    }

    @discardableResult public func status(_ status: ResponseStatus) -> Matcher {
        responder = StatusResponder(status: status)
        return self
    }

    @discardableResult public func resource(_ url: URL) -> Matcher {
        return self
    }

    @discardableResult public func resource(_ resource: String) throws -> Matcher {
        return self
    }

    @discardableResult public func resource(bundle: Bundle, resource: String) throws -> Matcher {
        return self
    }

    @discardableResult public func content(_ string: String, _ type: ContentType) -> Matcher {
        responder = ContentResponder(string: string, encoding: .utf8)
        return self
    }
    
    @discardableResult public func content(_ data: Data, _ type: ContentType) -> Matcher {
        responder = ContentResponder(data: data)
        return self
    }

    @discardableResult public func block(_ block: @escaping BlockResponder.BlockResponderBlock) -> Matcher {
        responder = BlockResponder(block: block)
        return self
    }

    @discardableResult public func json(_ value: Any) throws -> Matcher {
        let data = try JSONSerialization.data(withJSONObject: value)
        return content(data, .TextJSON)
    }

    @discardableResult public func then(_ block: () -> ()) -> Matcher {
        return self
    }

    func match(request: Request) -> Int? {
        guard match(path: request.path) else {
            return nil
        }

        guard let paramsScore = match(queryString: request.queryString) else {
            return nil
        }

        return paramsScore
    }

    private func match(path: String) -> Bool {
        guard let r = path.range(of: self.path, options: [.regularExpression, .anchored]) else {
            return false
        }

        /* Check anchoring at the end of the string, so our regex is a full match */
        if r.upperBound != path.endIndex {
            return false
        }

        return true
    }

    private func match(queryString: String?) -> Int? {
        var score = 0

        if let params = parse(queryString: queryString) {
            var remainingToMatch = self.params

            for (key, value) in params {
                if let requiredMatch = self.params[key] {
                    if let r = value.range(of: requiredMatch, options: [.regularExpression, .anchored]) {
                        /* Check anchoring at the end of the string, so our regex is a full match */
                        if r.upperBound != value.endIndex {
                            return nil
                        }

                        score += 1
                        remainingToMatch.removeValue(forKey: key)
                    } else {
                        return nil
                    }
                } else if !allowOtherParams {
                    return nil
                }
            }

            guard remainingToMatch.count == 0 else {
                return nil
            }
        } else if self.params.count != 0 {
            return nil
        }

        return score
    }
    
    private func parse(queryString: String?) -> [(String, String)]? {
        guard let queryString = queryString else {
            return nil
        }
        
        var result = [(String, String)]()

        for pair in queryString.components(separatedBy: "&") {
            let pairTuple = pair.components(separatedBy: "=")
            if pairTuple.count == 2 {
                result.append((pairTuple[0], pairTuple[1]))
            } else {
                result.append((pairTuple[0], ""))
            }
        }
        
        return result
    }

    func handle(request: Request) -> Response {
        do {
            if let responder = responder {
                if let response = try responder.respond(request: request) {
                    return response
                }
            }
            
            return Response(status: .notFound)
        } catch {
            print("Failed to generate response: \(error)")
            return Response(status: .internalServerError)
        }
    }

}

public enum RequestMethod: String {
    case GET
    case HEAD
    case POST
    case PUT
    case DELETE
}

public struct Request {

    public var method: String
    public var path: String
    public var queryString: String?
    public var headers: [(String, String)]?
    public var body: Data?
    public var contentType: ContentType? {
        return nil
    }

    public init(method: String = RequestMethod.GET.rawValue, path: String) {
        self.method = method
        self.path = path
    }

    public init(method: String = RequestMethod.GET.rawValue, path: String, queryString: String?) {
        self.method = method
        self.path = path
        self.queryString = queryString
    }
    
    public init(method: String = RequestMethod.GET.rawValue, path: String, queryString: String?, headers: [(String, String)]?) {
        self.method = method
        self.path = path
        self.queryString = queryString
        self.headers = headers
    }

}

public struct Response {

    public var status: ResponseStatus
    public var headers: [(String, String)]?
    public var data: Data?
    public var contentType: ContentType?
    
    public init(status: ResponseStatus) {
        self.status = status
    }
    
    public init(status: ResponseStatus, data: Data?, contentType: ContentType?) {
        self.status = status
        self.data = data
        self.contentType = contentType
    }
    
}

public enum ResponderError: Error {
    case ResourceNotFound(bundle: Bundle, resource: String)
}

public protocol Responder {

    typealias ResponderBlock = () -> ()
    
    func respond(request: Request) throws -> Response?
    
    func then(_ block: ResponderBlock)

}

extension Responder {
    
    public func then(_ block: ResponderBlock) {

    }
    
}

public class ResourceResponder: Responder {

    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public init(bundle: Bundle, resource: String) throws {
        if let url = bundle.url(forResource: resource, withExtension: nil) {
            self.url = url
        } else {
            throw ResponderError.ResourceNotFound(bundle: bundle, resource: resource)
        }
    }
    
    public func respond(request: Request) throws -> Response? {
        let data = try Data.init(contentsOf: url)
        return Response(status: .ok, data: data, contentType: .TextPlain)
    }
    
}

public class ContentResponder: Responder {

    private let data: Data
    
    public init(string: String, encoding: String.Encoding) {
        self.data = string.data(using: encoding)!
    }

    public init(data: Data) {
        self.data = data
    }
    
    public func respond(request: Request) -> Response? {
        return Response(status: .ok, data: data, contentType: .TextPlain)
    }
    
}

public class BlockResponder: Responder {
    
    public typealias BlockResponderBlock = (Request) -> (Response?)
    
    private let block: BlockResponderBlock
    
    public init(block: @escaping BlockResponderBlock) {
        self.block = block
    }
    
    public func respond(request: Request) throws -> Response? {
        return block(request)
    }
}

public class StatusResponder: Responder {
    
    private let status: ResponseStatus
    
    public init(status: ResponseStatus) {
        self.status = status
    }
    
    public func respond(request: Request) throws -> Response? {
        return Response(status: status)
    }
    
}
