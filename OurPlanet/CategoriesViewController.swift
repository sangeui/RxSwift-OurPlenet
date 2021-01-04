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

import UIKit
import RxSwift
import RxCocoa

class CategoriesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
  
  let categories = BehaviorRelay<[EOCategory]>(value: [])
  let disposeBag = DisposeBag()
  
  let indicatorView = UIActivityIndicatorView(style: .gray)
  let progressView = UIProgressView()
  
  @IBOutlet var tableView: UITableView!
  override func loadView() {
    super.loadView()
    indicatorView.translatesAutoresizingMaskIntoConstraints = false
    indicatorView.startAnimating()
    view.addSubview(indicatorView)
    
    indicatorView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
    indicatorView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    self.view.addSubview(progressView)
    progressView.translatesAutoresizingMaskIntoConstraints = false
    progressView.leadingAnchor.constraint(equalTo: tableView.leadingAnchor).isActive = true
    progressView.trailingAnchor.constraint(equalTo: tableView.trailingAnchor).isActive = true
    progressView.topAnchor.constraint(equalTo: tableView.topAnchor).isActive = true
    progressView.heightAnchor.constraint(equalToConstant: 5).isActive = true
    
    self.tableView.alpha = 0
    categories
      .asObservable()
      .subscribe(onNext: { [weak self] _ in
        DispatchQueue.main.async { self?.tableView.reloadData() }
      })
      .disposed(by: disposeBag)
    
    startDownload()
  }
  
  func startDownload() {
    let eoCategories = EONET.categories
    let downloadedEvents = eoCategories
      .do(
        onCompleted: {
          DispatchQueue.main.async {
            UIView.animate(withDuration: 0.5) {
              self.tableView.alpha = 1.0
            }
            self.indicatorView.stopAnimating()
          }
        })
      .flatMap { return Observable.from($0.map { return EONET.events(forLast: 360, category: $0) }) }
      .merge(maxConcurrent: 2)
    
    let updatedCategories = eoCategories.flatMap { categories in
      downloadedEvents.scan((0, categories)) { tuple, events in
        return (tuple.0 + 1, tuple.1.map { category in
          let eventsForCategory = EONET.filteredEvents(events: events, forCategory: category)
          if !eventsForCategory.isEmpty {
            var cat = category
            cat.events = cat.events + eventsForCategory
            return cat
          }
          return category
        })
      }
    }
    .do(
      onNext: { [weak self] tuple in
        guard let strongSelf = self else { return }
        DispatchQueue.main.async {
          let progress = Float(tuple.0) / Float(tuple.1.count)
          strongSelf.progressView.setProgress(progress, animated: true)
        }
      },
      onCompleted: { [weak self] in
        guard let strongSelf = self else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
          strongSelf.progressView.isHidden = true 
        }
      })
    
    eoCategories
      .concat(updatedCategories.map(\.1))
      .bind(to: categories)
      .disposed(by: disposeBag)
  }
  
  // MARK: UITableViewDataSource
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return categories.value.count
  }
  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    return "categories"
  }
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "categoryCell")!
    let category = categories.value[indexPath.row]
    
    cell.accessoryType = (category.events.count > 0) ? .disclosureIndicator : .none
    
    
    let countString = String(category.events.count)
    let fullString = category.name + " " + countString
    
    let range = (fullString as NSString).range(of: countString)
    
    let mutableAttributedString = NSMutableAttributedString.init(string: fullString)
    mutableAttributedString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.lightGray, range: range)
    mutableAttributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 8), range: range)
    
    
    cell.textLabel?.attributedText = mutableAttributedString
    cell.detailTextLabel?.text = category.description
    return cell
  }
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    let category = categories.value[indexPath.row]
    
    guard !category.events.isEmpty else { return }
    let eventsController = storyboard!.instantiateViewController(withIdentifier: "events") as! EventsViewController
    eventsController.title = category.name
    eventsController.events.accept(category.events)
    navigationController!.pushViewController(eventsController, animated: true)
  }
}

