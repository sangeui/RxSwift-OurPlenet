/// Copyright (c) 2020 Razeware LLC
/// 
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
/// 
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
/// 
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
/// 
/// This project and source code may use libraries or frameworks that are
/// released under various Open-Source licenses. Use of those libraries and
/// frameworks are governed by their own individual licenses.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import Foundation
import RxSwift
import RxCocoa

class EONET {
  typealias Query = [String: Any]
  typealias EndPoint = String
  typealias Identifier = String
  typealias HTTPResult = (response: HTTPURLResponse, data: Data)
  static let API = "https://eonet.sci.gsfc.nasa.gov/api/v2.1"
  static let categoriesEndpoint = "/categories"
  static let eventsEndpoint = "/events"
  
  static func jsonDecoder(contentIdentifier: String) -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.userInfo[.contentIdentifier] = contentIdentifier
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
  
  static func filteredEvents(events: [EOEvent], forCategory category: EOCategory) -> [EOEvent] {
    return events.filter { event in
      return event.categories.contains(where: { $0.id == category.id }) && !category.events.contains {
        $0.id == event.id
      }
    }
    .sorted(by: EOEvent.compareDates)
  }
  static func request<T: Decodable>(endpoint: EndPoint, query: Query = [:], identifier: Identifier) -> Observable<T> {
    do {
      var components = try makeURLComponents(API, endpoint)
      components.queryItems = try makeQueryItems(query)
      let url = try extractURL(from: components, endpoint)
      let request = URLRequest(url: url)
      return URLSession.shared.rx.response(request: request)
        .map({ try makeEnvelope(with: $0, identifier: identifier)})
    } catch { return Observable.empty() }
  }
}
extension EONET {
  static var categories: Observable<[EOCategory]> = {
    let request: Observable<[EOCategory]> = EONET.request(endpoint: categoriesEndpoint, identifier: "categories")
    return request
      .map({ $0.sorted(by: { $0.name < $1.name }) })
      .catchErrorJustReturn([])
      .share(replay: 1, scope: .forever)
  } ()
  static func events(forLast days: Int = 360, category: EOCategory) -> Observable<[EOEvent]> {
    let openEvents = events(forLast: days, closed: false, endPoint: category.endpoint)
    let closedEvents = events(forLast: days, closed: true, endPoint: category.endpoint)
    return Observable.of(openEvents, closedEvents)
      .merge()
      .reduce([], accumulator: +)
  }
  private static func events(forLast days: Int, closed: Bool, endPoint: String) -> Observable<[EOEvent]> {
    let query: [String: Any] = ["days": days, "status": (closed ? "closed" : "open")]
    let request: Observable<[EOEvent]> = EONET.request(endpoint: endPoint, query: query, identifier: "events")
    return request.catchErrorJustReturn([])
  }
}
private extension EONET {
  static func makeEnvelope<T: Decodable>(with result: HTTPResult, identifier: Identifier) throws -> T {
    let decoder = self.jsonDecoder(contentIdentifier: identifier)
    let envelope = try decoder.decode(EOEnvelope<T>.self, from: result.data)
    return envelope.content
  }
}
private extension EONET {
  static func makeQueryItems(_ query: EONET.Query) throws -> [URLQueryItem] {
    return try query.compactMap { (key, value) in
      guard let v = value as? CustomStringConvertible else {
        throw EOError.invalidParameter(key, value)
      }
      return URLQueryItem(name: key, value: v.description)
    }
  }
}
private extension EONET {
  static func extractURL(from components: URLComponents, _ messageWhenFailed: String) throws -> URL {
    guard let url = components.url else { throw EOError.invalidURL(messageWhenFailed)}
    return url
  }
  static func makeURLComponents(_ urlString: String, _ path: String) throws -> URLComponents {
    guard let urlComponents = urlComponents(urlString, path) else { throw EOError.invalidURL(urlString) }
    return urlComponents
  }
  static func urlComponents(_ urlString: String, _ path: String) -> URLComponents? {
    if let url = urlAppended(by: path, urlString), let components = urlComponentized(url) { return components }
    else { return nil }
  }
  static func urlAppended(by path: String, _ urlString: String) -> URL? {
    return URL(string: urlString)?.appendingPathComponent(path)
  }
  static func urlComponentized(_ url: URL) -> URLComponents? {
    return URLComponents(url: url, resolvingAgainstBaseURL: true)
  }
}
